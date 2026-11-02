/*
 * softmmu size bounds
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#ifndef ACCEL_TCG_TLB_BOUNDS_H
#define ACCEL_TCG_TLB_BOUNDS_H

#define CPU_TLB_DYN_MIN_BITS 6
#define CPU_TLB_DYN_MAX_BITS (32 - TARGET_PAGE_BITS)
/*
 * Optimized: start each softmmu TLB at 2^10 entries instead of 2^8.
 * The TLB resizes dynamically (see tlb_mmu_resize_locked), so this only
 * removes the warm-up phase of repeated flush+double cycles after boot or
 * after the guest switches address spaces. Upstream default is 8.
 */
#define CPU_TLB_DYN_DEFAULT_BITS 10

#endif /* ACCEL_TCG_TLB_BOUNDS_H */
