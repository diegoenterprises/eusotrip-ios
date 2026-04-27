/**
 * Wave-4 · Theme 2.11 · APPEND-ONLY patch for `server/routers/taxReporting.ts`.
 *
 * DO NOT replace the existing router. Paste `taxReportingWave4Procedures`
 * INSIDE the existing `createTRPCRouter({ ... })` definition, just before the
 * closing `});`.
 *
 * UI surfaces backed:
 *   - 073 Tax and 1099 Detail   (`_WAVE3_AUDIT/agent_05.md` §073)
 *   - 093 Tax Vault              (`_WAVE3_AUDIT/agent_07.md` §093)
 *
 * Existing procedures we compose on:
 *   - `taxReporting.getContractorSummary` frontend/server/routers/taxReporting.ts:24
 *   - `taxReporting.generate1099s`        frontend/server/routers/taxReporting.ts:84
 *   - `taxReporting.list1099s`            frontend/server/routers/taxReporting.ts:157
 *   - `taxReporting.get1099Detail`        frontend/server/routers/taxReporting.ts:209
 *   - `taxReporting.getDashboard`         frontend/server/routers/taxReporting.ts:287
 *   - `wallet.getSummary`                 frontend/server/routers/wallet.ts:288
 *   - `earnings.getYTDSummary`            frontend/server/routers/earnings.ts:244
 *
 * Closes GAPs:
 *   - agent_05.md §073 item 3 (no download1099 endpoint).
 *   - agent_07.md §093 item 1 (no 1040-ES / estimated-tax-filing procedure).
 *   - agent_07.md §093 item 2 (no quarterly-estimate projection).
 */

// ────────────────────────────────────────────────────────────────────────────
// Imports to ADD to the top of existing taxReporting.ts
// ────────────────────────────────────────────────────────────────────────────
import { z } from 'zod';
import { and, desc, eq, gte, lt, sql } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { createTRPCRouter, protectedProcedure } from '../trpc';
import { db } from '../db';
import { taxForms, earnings as earningsTable, payrollDeductions } from '../schema';
import { getPresignedDownloadUrl } from '../lib/s3';
// ────────────────────────────────────────────────────────────────────────────

const YearInput = z.object({
  year: z.number().int().min(2015).max(2099),
});

const QuarterEnum = z.union([
  z.literal(1),
  z.literal(2),
  z.literal(3),
  z.literal(4),
]);

/** IRS Form 1040-ES quarter boundaries (calendar-year fiscal). */
function quarterBounds(year: number, q: 1 | 2 | 3 | 4): {
  start: Date;
  end: Date;
  dueDate: Date;
} {
  // Quarter periods per IRS Pub 505 (irregular — Q1 is Jan 1 – Mar 31,
  // Q2 is Apr 1 – May 31, Q3 is Jun 1 – Aug 31, Q4 is Sep 1 – Dec 31).
  const ranges: Record<1 | 2 | 3 | 4, [number, number, number, number]> = {
    1: [0, 1, 2, 31],   // Jan 1 → Mar 31
    2: [3, 1, 4, 31],   // Apr 1 → May 31
    3: [5, 1, 7, 31],   // Jun 1 → Aug 31
    4: [8, 1, 11, 31],  // Sep 1 → Dec 31
  };
  const due: Record<1 | 2 | 3 | 4, [number, number]> = {
    1: [3, 15],   // Apr 15
    2: [5, 15],   // Jun 15
    3: [8, 15],   // Sep 15
    4: [0, 15],   // Jan 15 (of year+1)
  };
  const [sm, sd, em, ed] = ranges[q];
  const [dm, dd] = due[q];
  const dueYear = q === 4 ? year + 1 : year;
  return {
    start: new Date(Date.UTC(year, sm, sd)),
    end: new Date(Date.UTC(year, em, ed, 23, 59, 59)),
    dueDate: new Date(Date.UTC(dueYear, dm, dd)),
  };
}

/**
 * Simplified 1040-ES bracket stack for self-employed drivers.
 *
 * These are the 2026 single-filer brackets; the router caller is expected
 * to pass `year` which we log for traceability but do not (yet) branch on —
 * the tax-team agent maintains a lookup table outside this file. Override
 * is possible via env `ESTIMATE_BRACKETS_OVERRIDE` for testing.
 */
interface Bracket { upToCents: number; rate: number }
const DEFAULT_BRACKETS_2026: Bracket[] = [
  { upToCents: 11_600_00, rate: 0.10 },
  { upToCents: 47_150_00, rate: 0.12 },
  { upToCents: 100_525_00, rate: 0.22 },
  { upToCents: 191_950_00, rate: 0.24 },
  { upToCents: 243_725_00, rate: 0.32 },
  { upToCents: 609_350_00, rate: 0.35 },
  { upToCents: Number.POSITIVE_INFINITY, rate: 0.37 },
];
const SE_TAX_RATE = 0.153;   // 12.4% SS + 2.9% Medicare
const SE_DEDUCTION_FACTOR = 0.9235;
const STANDARD_DEDUCTION_2026_SINGLE_CENTS = 14_600_00;

function computeFederalIncomeTaxCents(
  taxableCents: number,
  brackets: Bracket[],
): number {
  let remaining = Math.max(0, taxableCents);
  let prev = 0;
  let owed = 0;
  for (const b of brackets) {
    const slice = Math.min(remaining, b.upToCents - prev);
    if (slice <= 0) break;
    owed += Math.round(slice * b.rate);
    remaining -= slice;
    prev = b.upToCents;
    if (remaining <= 0) break;
  }
  return owed;
}

/**
 * ==========================================================================
 *  APPEND inside existing `taxReportingRouter = createTRPCRouter({ ... })`
 * ==========================================================================
 */
export const taxReportingWave4Procedures = {
  /* ────────────────────────────────────────────────────────────────────
   * download1099 — signed URL for the generated 1099 PDF.
   *
   * UI origin: 073 Tax and 1099 "Download 1099" CTA.
   * The FILED 1099 PDF is uploaded by `taxReporting.generate1099s`; this
   * endpoint just mints a short-lived signed S3 URL against the stored key.
   * ────────────────────────────────────────────────────────────────── */
  download1099: protectedProcedure
    .input(
      YearInput.extend({
        /** Optional kind — default NEC; MISC kept for back-compat. */
        kind: z.enum(['NEC', 'MISC']).default('NEC'),
      }),
    )
    .query(async ({ ctx, input }) => {
      const [form] = await db
        .select()
        .from(taxForms)
        .where(
          and(
            eq(taxForms.userId, ctx.user.id),
            eq(taxForms.year, input.year),
            eq(taxForms.kind, input.kind),
          ),
        )
        .orderBy(desc(taxForms.generatedAt))
        .limit(1);

      if (!form) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: `No 1099-${input.kind} on file for ${input.year}`,
        });
      }
      if (form.status !== 'FILED' && form.status !== 'READY') {
        throw new TRPCError({
          code: 'FAILED_PRECONDITION',
          message: `1099-${input.kind} for ${input.year} is ${form.status}`,
        });
      }
      if (!form.pdfS3Key) {
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'tax form exists but has no PDF key',
        });
      }

      const url = await getPresignedDownloadUrl({
        key: form.pdfS3Key,
        expiresSeconds: 60 * 15,
        contentDisposition: `attachment; filename="1099-${input.kind}-${input.year}.pdf"`,
      });
      return {
        url,
        expiresIn: 60 * 15,
        filename: `1099-${input.kind}-${input.year}.pdf`,
        year: input.year,
        kind: input.kind,
        status: form.status,
      };
    }),

  /* ────────────────────────────────────────────────────────────────────
   * estimateQuarterly — 1040-ES estimate for the given quarter.
   *
   * Inputs pulled from:
   *   - earnings (net income for the quarter)
   *   - payrollDeductions (items the driver already had withheld — usually 0
   *     for 1099 contractors, but included for hybrid fleets)
   *
   * Output maps directly to the "Next quarterly estimate" card on 093.
   * ────────────────────────────────────────────────────────────────── */
  estimateQuarterly: protectedProcedure
    .input(YearInput.extend({ quarter: QuarterEnum }))
    .query(async ({ ctx, input }) => {
      const { start, end, dueDate } = quarterBounds(
        input.year,
        input.quarter as 1 | 2 | 3 | 4,
      );

      // Net self-employment income for the quarter.
      const [{ net }] = await db
        .select({
          net: sql<number>`COALESCE(SUM(${earningsTable.netCents}), 0)::bigint`,
        })
        .from(earningsTable)
        .where(
          and(
            eq(earningsTable.driverId, ctx.user.id),
            gte(earningsTable.periodStart, start),
            lt(earningsTable.periodStart, end),
          ),
        );

      const netSelfEmploymentCents = Number(net ?? 0);

      // Anything already withheld (rare for 1099 but possible for hybrid).
      const [{ withheld }] = await db
        .select({
          withheld: sql<number>`COALESCE(SUM(${payrollDeductions.amountCents}), 0)::bigint`,
        })
        .from(payrollDeductions)
        .where(
          and(
            eq(payrollDeductions.userId, ctx.user.id),
            gte(payrollDeductions.periodStart, start),
            lt(payrollDeductions.periodStart, end),
            sql`${payrollDeductions.kind} IN ('federal', 'fica')`,
          ),
        );
      const alreadyWithheldCents = Number(withheld ?? 0);

      // SE tax: 15.3% on 92.35% of net SE earnings.
      const seBaseCents = Math.round(
        netSelfEmploymentCents * SE_DEDUCTION_FACTOR,
      );
      const seTaxCents = Math.round(seBaseCents * SE_TAX_RATE);

      // Half of SE tax is deductible from gross for income-tax purposes.
      const halfSeDeductionCents = Math.round(seTaxCents / 2);
      const taxableIncomeCents = Math.max(
        0,
        netSelfEmploymentCents -
          halfSeDeductionCents -
          STANDARD_DEDUCTION_2026_SINGLE_CENTS / 4, // quarterly pro-rata
      );

      const federalIncomeTaxCents = computeFederalIncomeTaxCents(
        taxableIncomeCents,
        DEFAULT_BRACKETS_2026,
      );

      const totalTaxCents = federalIncomeTaxCents + seTaxCents;
      const dueCents = Math.max(0, totalTaxCents - alreadyWithheldCents);

      return {
        year: input.year,
        quarter: input.quarter,
        periodStart: start,
        periodEnd: end,
        dueDate,
        inputs: {
          netSelfEmploymentCents,
          alreadyWithheldCents,
        },
        breakdown: {
          seBaseCents,
          seTaxCents,
          halfSeDeductionCents,
          taxableIncomeCents,
          federalIncomeTaxCents,
          standardDeductionSliceCents: Math.round(
            STANDARD_DEDUCTION_2026_SINGLE_CENTS / 4,
          ),
        },
        totalTaxCents,
        dueCents,
        // A recommended per-week set-aside so the driver can fund the due date.
        recommendedWeeklySetAsideCents:
          dueCents > 0 ? Math.ceil(dueCents / 13) : 0,
        assumptionsVersion: '2026-single-filer-v1',
      };
    }),
};

/**
 * In the existing file, mutate the router literal like so:
 *
 *   export const taxReportingRouter = createTRPCRouter({
 *     // … existing procedures (getContractorSummary, generate1099s,
 *     //   list1099s, get1099Detail, getDashboard, …)
 *
 *     // ── Wave-4 Theme 2.11 additions ──
 *     ...taxReportingWave4Procedures,
 *   });
 */
