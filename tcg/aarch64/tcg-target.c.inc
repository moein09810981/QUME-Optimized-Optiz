};

static void tgen_eqv(TCGContext *s, TCGType type,
                     TCGReg a0, TCGReg a1, TCGReg a2)
{
    tcg_out_insn(s, logic_shift, EON, type, a0, a1, a2);
}

static const TCGOutOpBinary outop_eqv = {
    .base.static_constraint = C_O1_I2(r, r, r),
    .out_rrr = tgen_eqv,
};

static void tgen_extrh_i64_i32(TCGContext *s, TCGType t, TCGReg a0, TCGReg a1)
{
    tcg_out_ubfm(s, TCG_TYPE_I64, a0, a1, 32, 63);
}

static const TCGOutOpUnary outop_extrh_i64_i32 = {
    .base.static_constraint = C_O1_I1(r, r),
    .out_rr = tgen_extrh_i64_i32,
};

static void tgen_mul(TCGContext *s, TCGType type,
                     TCGReg a0, TCGReg a1, TCGReg a2)
{
    tcg_out_insn(s, rrrr, MADD, type, a0, a1, a2, TCG_REG_XZR);
}

static const TCGOutOpBinary outop_mul = {
    .base.static_constraint = C_O1_I2(r, r, r),
    .out_rrr = tgen_mul,
};

/*
 * AArch64 has separate low- and high-half multiply instructions.  Emit
 * both directly so TCG does not need a temporary plus a separate move
 * when lowering the two-result operation.
 *
 * The low result is written before the high multiply reads its operands,
 * so it must not overlap either input.  The high result is written by the
 * second instruction and may overlap an input.
 */
static void tgen_muls2(TCGContext *s, TCGType type,
                       TCGReg rl, TCGReg rh, TCGReg a, TCGReg b)
{
    tcg_out_insn(s, rrrr, MADD, TCG_TYPE_I64, rl, a, b, TCG_REG_XZR);
    tcg_out_insn(s, rrr, SMULH, TCG_TYPE_I64, rh, a, b);
}

static TCGConstraintSetIndex cset_muls2(TCGType type, unsigned flags)
{
    return type == TCG_TYPE_I64 ? C_O2_I2(&r, r, r, r) : C_NotImplemented;
}

static const TCGOutOpMul2 outop_muls2 = {
    .base.static_constraint = C_Dynamic,
    .base.dynamic_constraint = cset_muls2,
    .out_rrrr = tgen_muls2,
};

static TCGConstraintSetIndex cset_mulh(TCGType type, unsigned flags)
{
    return type == TCG_TYPE_I64 ? C_O1_I2(r, r, r) : C_NotImplemented;
}

static void tgen_mulsh(TCGContext *s, TCGType type,
                       TCGReg a0, TCGReg a1, TCGReg a2)
{
    tcg_out_insn(s, rrr, SMULH, TCG_TYPE_I64, a0, a1, a2);
}

static const TCGOutOpBinary outop_mulsh = {
    .base.static_constraint = C_Dynamic,
    .base.dynamic_constraint = cset_mulh,
    .out_rrr = tgen_mulsh,
};

static void tgen_mulu2(TCGContext *s, TCGType type,
                       TCGReg rl, TCGReg rh, TCGReg a, TCGReg b)
{
    tcg_out_insn(s, rrrr, MADD, TCG_TYPE_I64, rl, a, b, TCG_REG_XZR);
    tcg_out_insn(s, rrr, UMULH, TCG_TYPE_I64, rh, a, b);
}

static TCGConstraintSetIndex cset_mulu2(TCGType type, unsigned flags)
{
    return type == TCG_TYPE_I64 ? C_O2_I2(&r, r, r, r) : C_NotImplemented;
}

static const TCGOutOpMul2 outop_mulu2 = {
    .base.static_constraint = C_Dynamic,
    .base.dynamic_constraint = cset_mulu2,
    .out_rrrr = tgen_mulu2,
};

static void tgen_muluh(TCGContext *s, TCGType type,
                       TCGReg a0, TCGReg a1, TCGReg a2)
{
    tcg_out_insn(s, rrr, UMULH, TCG_TYPE_I64, a0, a1, a2);
}

static const TCGOutOpBinary outop_muluh = {
    .base.static_constraint = C_Dynamic,
    .base.dynamic_constraint = cset_mulh,
    .out_rrr = tgen_muluh,
};

static const TCGOutOpBinary outop_nand = {
    .base.static_constraint = C_NotImplemented,
};

static const TCGOutOpBinary outop_nor = {
    .base.static_constraint = C_NotImplemented,
};

static void tgen_or(TCGContext *s, TCGType type,
                    TCGReg a0, TCGReg a1, TCGReg a2)
{
    tcg_out_insn(s, logic_shift, ORR, type, a0, a1, a2);
}

static void tgen_ori(TCGContext *s, TCGType type,
                     TCGReg a0, TCGReg a1, tcg_target_long a2)
{
    tcg_out_logicali(s, Ilogic_imm_ORRI, type, a0, a1, a2);
}

static const TCGOutOpBinary outop_or = {
    .base.static_constraint = C_O1_I2(r, r, rL),
    .out_rrr = tgen_or,
    .out_rri = tgen_ori,
};

static void tgen_orc(TCGContext *s, TCGType type,
                     TCGReg a0, TCGReg a1, TCGReg a2)
{
    tcg_out_insn(s, logic_shift, ORN, type, a0, a1, a2);