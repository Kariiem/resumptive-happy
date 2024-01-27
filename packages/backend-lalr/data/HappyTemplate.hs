-- $Id: GenericTemplate.hs,v 1.26 2005/01/14 14:47:22 simonmar Exp $

#ifdef HAPPY_GHC
#  if !defined(__GLASGOW_HASKELL__)
#    error `HAPPY_GHC` is defined but this code isn't being built with GHC.
#  endif
#  define ILIT(n) n#
#  define IBOX(n) (Happy_GHC_Exts.I# (n))
#  define FAST_INT Happy_GHC_Exts.Int#
-- Do not remove this comment. Required to fix CPP parsing when using GCC and a clang-compiled alex.
#  if __GLASGOW_HASKELL__ > 706
#    define LT(n,m) ((Happy_GHC_Exts.tagToEnum# (n Happy_GHC_Exts.<# m)) :: Prelude.Bool)
#    define GTE(n,m) ((Happy_GHC_Exts.tagToEnum# (n Happy_GHC_Exts.>=# m)) :: Prelude.Bool)
#    define EQ(n,m) ((Happy_GHC_Exts.tagToEnum# (n Happy_GHC_Exts.==# m)) :: Prelude.Bool)
#  else
#    define LT(n,m) (n Happy_GHC_Exts.<# m)
#    define GTE(n,m) (n Happy_GHC_Exts.>=# m)
#    define EQ(n,m) (n Happy_GHC_Exts.==# m)
#  endif
#  define PLUS(n,m) (n Happy_GHC_Exts.+# m)
#  define MINUS(n,m) (n Happy_GHC_Exts.-# m)
#  define TIMES(n,m) (n Happy_GHC_Exts.*# m)
#  define NEGATE(n) (Happy_GHC_Exts.negateInt# (n))
#  define IF_GHC(x) (x)
#else
#  define ILIT(n) (n)
#  define IBOX(n) (n)
#  define FAST_INT Prelude.Int
#  define LT(n,m) (n Prelude.< m)
#  define GTE(n,m) (n Prelude.>= m)
#  define EQ(n,m) (n Prelude.== m)
#  define PLUS(n,m) (n Prelude.+ m)
#  define MINUS(n,m) (n Prelude.- m)
#  define TIMES(n,m) (n Prelude.* m)
#  define NEGATE(n) (Prelude.negate (n))
#  define IF_GHC(x)
#endif

data Happy_IntList = HappyCons FAST_INT Happy_IntList

#if defined(HAPPY_ARRAY)
#  define CONS(h,t) (HappyCons (h) (t))
#else
#  define CONS(h,t) ((h):(t))
#endif

#if defined(HAPPY_ARRAY)
#  define ERROR_TOK ILIT(0)
#  define CATCH_TOK ILIT(1)
#  define DO_ACTION(state,i,tk,sts,stk) happyDoAction i tk state sts (stk)
#  define HAPPYSTATE(i) (i)
#  define GOTO(action) happyGoto
#  define IF_ARRAY(x) (x)
#else
#  define ERROR_TOK ILIT(1)
#  define CATCH_TOK ILIT(2)
#  define DO_ACTION(state,i,tk,sts,stk) state i i tk HAPPYSTATE(state) sts (stk)
#  define HAPPYSTATE(i) (HappyState (i))
#  define GOTO(action) action
#  define IF_ARRAY(x)
#endif

#if defined(HAPPY_COERCE)
#  if !defined(HAPPY_GHC)
#    error `HAPPY_COERCE` requires `HAPPY_GHC`
#  endif
#  define GET_ERROR_TOKEN(x)  (case Happy_GHC_Exts.unsafeCoerce# x of { IBOX(i) -> i })
#  define MK_ERROR_TOKEN(i)   (Happy_GHC_Exts.unsafeCoerce# IBOX(i))
#  define MK_TOKEN(x)         (happyInTok (x))
#else
#  define GET_ERROR_TOKEN(x)  (case x of { HappyErrorToken IBOX(i) -> i })
#  define MK_ERROR_TOKEN(i)   (HappyErrorToken IBOX(i))
#  define MK_TOKEN(x)         (HappyTerminal (x))
#endif

#if defined(HAPPY_DEBUG)
#  define DEBUG_TRACE(s)    (happyTrace (s)) $
happyTrace string expr = Happy_System_IO_Unsafe.unsafePerformIO $ do
    Happy_System_IO.hPutStr Happy_System_IO.stderr string
    return expr
#else
#  define DEBUG_TRACE(s)    {- nothing -}
#endif

infixr 9 `HappyStk`
data HappyStk a = HappyStk a (HappyStk a)

-----------------------------------------------------------------------------
-- starting the parse

happyParse start_state = happyNewToken start_state notHappyAtAll notHappyAtAll

-----------------------------------------------------------------------------
-- Accepting the parse

-- If the current token is ERROR_TOK, it means we've just accepted a partial
-- parse (a %partial parser).  We must ignore the saved token on the top of
-- the stack in this case.
happyAccept ERROR_TOK tk st sts (_ `HappyStk` ans `HappyStk` _) =
        happyReturn1 ans
happyAccept j tk st sts (HappyStk ans _) =
        IF_GHC(happyTcHack j IF_ARRAY(happyTcHack st)) (happyReturn1 ans)

-----------------------------------------------------------------------------
-- Arrays only: do the next action

#if defined(HAPPY_ARRAY)

happyDoAction i tk st =
  DEBUG_TRACE("state: " ++ show IBOX(st) ++
              ",\ttoken: " ++ show IBOX(i) ++
              ",\taction: ")
  case happyDecodeAction (happyNextAction i st) of
    HappyFail   -> DEBUG_TRACE("failing.\n")
                   happyFail st i tk st
    HappyAccept -> DEBUG_TRACE("accept.\n")
                   happyAccept i tk st
    HappyReduce rule -> DEBUG_TRACE("reduce (rule " ++ show IBOX(rule) ++ ")")
                        (happyReduceArr Happy_Data_Array.! IBOX(rule)) i tk st
    HappyShift  new_state -> DEBUG_TRACE("shift, enter state " ++ show IBOX(new_state) ++ "\n")
                             happyShift new_state i tk st

{-# INLINE happyNextAction #-}
happyNextAction i st = case happyIndexActionTable i st of
  Just (IBOX(act)) -> act
  Nothing          -> indexShortOffAddr happyDefActions st

{-# INLINE happyIndexActionTable #-}
happyIndexActionTable i st
  | GTE(off,ILIT(0)), EQ(indexShortOffAddr happyCheck off, i)
  = Prelude.Just (IBOX(indexShortOffAddr happyTable off))
  | otherwise
  = Prelude.Nothing
  where
    off = PLUS(happyAdjustOffset (indexShortOffAddr happyActOffsets st), i)

data HappyAction
  = HappyFail
  | HappyAccept
  | HappyReduce FAST_INT -- rule number
  | HappyShift FAST_INT  -- new state

{-# INLINE happyDecodeAction #-}
happyDecodeAction ILIT(0)  = HappyFail
happyDecodeAction ILIT(-1) = HappyAccept
happyDecodeAction action
  | LT(action,ILIT(0))
  = HappyReduce NEGATE(PLUS(action,ILIT(1)))
  | otherwise
  = HappyShift MINUS(action,ILIT(1))

{-# INLINE happyIndexGotoTable #-}
happyIndexGotoTable nt st = indexShortOffAddr happyTable off
  where
    off = PLUS(happyAdjustOffset (indexShortOffAddr happyGotoOffsets st), nt)

#endif /* HAPPY_ARRAY */

#ifdef HAPPY_GHC
indexShortOffAddr (HappyA# arr) off =
        Happy_GHC_Exts.narrow16Int# i
  where
        i = Happy_GHC_Exts.word2Int# (Happy_GHC_Exts.or# (Happy_GHC_Exts.uncheckedShiftL# high 8#) low)
        high = Happy_GHC_Exts.int2Word# (Happy_GHC_Exts.ord# (Happy_GHC_Exts.indexCharOffAddr# arr (off' Happy_GHC_Exts.+# 1#)))
        low  = Happy_GHC_Exts.int2Word# (Happy_GHC_Exts.ord# (Happy_GHC_Exts.indexCharOffAddr# arr off'))
        off' = off Happy_GHC_Exts.*# 2#
#else
indexShortOffAddr arr off = arr Happy_Data_Array.! off
#endif

{-# INLINE happyLt #-}
happyLt x y = LT(x,y)

#ifdef HAPPY_GHC
readArrayBit arr bit =
    Bits.testBit IBOX(indexShortOffAddr arr ((unbox_int bit) `Happy_GHC_Exts.iShiftRA#` 4#)) (bit `Prelude.mod` 16)
  where unbox_int (Happy_GHC_Exts.I# x) = x
#else
readArrayBit arr bit =
    Bits.testBit IBOX(indexShortOffAddr arr (bit `Prelude.div` 16)) (bit `Prelude.mod` 16)
#endif

#ifdef HAPPY_GHC
data HappyAddr = HappyA# Happy_GHC_Exts.Addr#
#endif

-----------------------------------------------------------------------------
-- HappyState data type (not arrays)

#if !defined(HAPPY_ARRAY)

newtype HappyState b c = HappyState
        (FAST_INT ->                    -- token number
         FAST_INT ->                    -- token number (yes, again)
         b ->                           -- token semantic value
         HappyState b c ->              -- current state
         [HappyState b c] ->            -- state stack
         c)

#endif

-----------------------------------------------------------------------------
-- Shifting a token

happyShift new_state ERROR_TOK tk st sts stk@(x `HappyStk` _) =
     let i = GET_ERROR_TOKEN(x) in
     DEBUG_TRACE("shifting the error token")
     DO_ACTION(new_state,i,tk,CONS(st,sts),stk)
happyShift new_state i tk st sts stk =
     happyNewToken new_state CONS(st,sts) (MK_TOKEN(tk)`HappyStk`stk)

-- happyReduce is specialised for the common cases.

happySpecReduce_0 nt fn j tk st@(HAPPYSTATE(action)) sts stk
     = happySeq fn (GOTO(action) nt j tk st CONS(st,sts) (fn `HappyStk` stk))

happySpecReduce_1 nt fn j tk old_st sts@(CONS(st@HAPPYSTATE(action),_)) (v1`HappyStk`stk')
     = let r = fn v1 in
       IF_ARRAY(happyTcHack old_st) happySeq r (GOTO(action) nt j tk st sts (r `HappyStk` stk'))

happySpecReduce_2 nt fn j tk old_st CONS(_,sts@(CONS(st@HAPPYSTATE(action),_))) (v1`HappyStk`v2`HappyStk`stk')
     = let r = fn v1 v2 in
       IF_ARRAY(happyTcHack old_st) happySeq r (GOTO(action) nt j tk st sts (r `HappyStk` stk'))

happySpecReduce_3 nt fn j tk old_st CONS(_,CONS(_,sts@(CONS(st@HAPPYSTATE(action),_)))) (v1`HappyStk`v2`HappyStk`v3`HappyStk`stk')
     = let r = fn v1 v2 v3 in
       IF_ARRAY(happyTcHack old_st) happySeq r (GOTO(action) nt j tk st sts (r `HappyStk` stk'))

happyReduce k nt fn j tk st sts stk =
      case happyDrop k CONS(st,sts) of
         sts1@(CONS(st1@HAPPYSTATE(action),_)) ->
                let r = fn stk in  -- it doesn't hurt to always seq here...
                happyDoSeq r (GOTO(action) nt j tk st1 sts1 r)

happyMonadReduce k nt fn j tk st sts stk =
      case happyDrop k CONS(st,sts) of
        sts1@(CONS(st1@HAPPYSTATE(action),_)) ->
          let drop_stk = happyDropStk k stk in
          happyThen1 (fn stk tk) (\r -> GOTO(action) nt j tk st1 sts1 (r `HappyStk` drop_stk))

happyMonad2Reduce k nt fn j tk st sts stk =
      j `happyTcHack` case happyDrop k CONS(st,sts) of
        sts1@(CONS(st1@HAPPYSTATE(action),_)) ->
         let drop_stk = happyDropStk k stk
#if defined(HAPPY_ARRAY)
             new_state = happyIndexGotoTable nt st1
#else
             _ = nt :: FAST_INT
             new_state = action
#endif
          in
          happyThen1 (fn stk tk) (\r -> happyNewToken new_state sts1 (r `HappyStk` drop_stk))

happyDrop ILIT(0) l = l
happyDrop n CONS(_,t) = happyDrop MINUS(n,(ILIT(1) :: FAST_INT)) t

happyDropStk ILIT(0) l = l
happyDropStk n (x `HappyStk` xs) = happyDropStk MINUS(n,(ILIT(1)::FAST_INT)) xs

-----------------------------------------------------------------------------
-- Moving to a new state after a reduction

#if defined(HAPPY_ARRAY)
happyGoto nt j tk st =
   DEBUG_TRACE(", goto state " ++ show IBOX(new_state) ++ "\n")
   happyDoAction j tk new_state where new_state = (happyIndexGotoTable nt st)
#else
happyGoto action j tk st = action j j tk (HappyState action)
#endif

-----------------------------------------------------------------------------
-- Error recovery
--
-- When there is no applicable action for the current lookahead token `tk`,
-- happy enters error recovery mode. It works in 2 phases:
--
--  1. Fixup: Try to see if there is an action for the error token (`errorTok`,
--     which is ERROR_TOK). If there is, do *not* emit an error and pretend
--     instead that an `errorTok` was inserted.
--     When there is no `errorTok` action, call the error handler
--     (e.g., `happyError`) with the resumption continuation `happyResume`.
--  2. Error resumption mode: If the error handler wants to resume parsing in
--     order to report multiple parse errors, it will call the resumption
--     continuation (of result type `P (Maybe a)`).
--     In the absence of the %resumptive declaration, this resumption will
--     always (do a bit of work, and) `return Nothing`.
--     In the presence of the %resumptive declaration, the grammar author
--     can use the special `catch` terminal to declare where parsing should
--     resume after an error.
--     E.g., if `stmt : expr ';' | catch ';'` then the resumption will
--
--       (a) Pop off the state stack until it finds an item
--             `stmt -> . catch ';'`.
--           Then, it will push a `catchTok` onto the stack, perform a shift and
--           end up in item `stmt -> catch . ';'`.
--       (b) Discard tokens from the lexer until it finds ';'.
--           (In general, it will discard until the lookahead has a non-default
--           action in the matches a token that applies
--           in the situation `P -> α catch . β`, where β might empty.)
--
-- The `catch` resumption mechanism (2) is what usually is associated with
-- `error` in `bison` or `menhir`. Since `error` is used for the Fixup mechanism
-- (1) above, we call the corresponding token `catch`.

-- Enter error Fixup: generate an error token,
--                    save the old token and carry on.
--                    When a `happyShift` accepts, we will pop off the error
--                    token to resume parsing with the current lookahead `i`.
happyTryFixup i tk HAPPYSTATE(action) sts stk =
  DEBUG_TRACE("entering `error` fixup.\n")
  DO_ACTION(action,ERROR_TOK,tk,sts, MK_ERROR_TOKEN(i) `HappyStk` stk)
  -- NB: `happyShift` will simply pop the error token and carry on with
  --     `tk`. Hence we don't change `tk` in the call here

-- parse error if we are in fixup and fail again
happyFixupFailed state_num tk st sts (x `HappyStk` stk) =
  let i = GET_ERROR_TOKEN(x) in
  DEBUG_TRACE("`error` fixup failed.\n")
#if defined(HAPPY_ARRAY)
  -- TODO: Walk the stack instead of looking only at the top state_num
  happyError_ i tk (happyExpListPerState (IBOX(state_num))) (happyResume i tk st sts stk)
#else
  happyError_ i tk (happyExpListPerState (IBOX(state_num))) (happyResume i tk st sts stk)
#endif

happyFail state_num ERROR_TOK = happyFixupFailed state_num
happyFail _         i         = happyTryFixup i

#if defined(HAPPY_ARRAY)
happyResume i tk st sts stk = pop_items st sts stk
  where
    pop_items st sts stk
      | HappyShift new_state <- happyDecodeAction (happyNextAction CATCH_TOK st)
      = DEBUG_TRACE("shifting catch token " ++ show IBOX(st) ++ " -> " ++ show IBOX(new_state) ++ "\n")
        discard_input_until_exp i tk new_state CONS(st,sts) (MK_ERROR_TOKEN(i) `HappyStk` stk)
      | DEBUG_TRACE("can't shift catch in " ++ show IBOX(st) ++ ", ") True
      , IBOX(n_starts) <- happy_n_starts, LT(st, n_starts)
      = DEBUG_TRACE("because it is a start state. no resumption.\n")
        happyReturn1 Nothing
      | CONS(st1,sts1) <- sts, _ `HappyStk` stk1 <- stk
      = DEBUG_TRACE("discarding.\n")
        pop_items st1 sts1 stk1
--    discard_input_until_exp :: Happy_GHC_Exts.Int# -> Token -> Happy_GHC_Exts.Int#  -> _
    discard_input_until_exp i tk st sts stk
      | HappyFail <- happyDecodeAction (happyNextAction i st)
      = DEBUG_TRACE("discard token in state " ++ show IBOX(st) ++ ": " ++ show IBOX(i) ++ "\n")
        happyLex (\_eof_tk -> happyReturn1 Nothing)
                 (\i tk -> discard_input_until_exp i tk st sts stk) -- not eof
      | otherwise
      = DEBUG_TRACE("found expected token in state " ++ show IBOX(st) ++ ": " ++ show IBOX(i) ++ "\n")
        happyFmap1 (\a -> a `happySeq` Just a)
                   (DO_ACTION(st,i,tk,sts,stk))
#else
happyResume (i :: FAST_INT) tk st sts stk = happyReturn1 Nothing
#endif


-- Internal happy errors:

notHappyAtAll :: a
notHappyAtAll = Prelude.error "Internal Happy error\n"

-----------------------------------------------------------------------------
-- Hack to get the typechecker to accept our action functions

#if defined(HAPPY_GHC)
happyTcHack :: Happy_GHC_Exts.Int# -> a -> a
happyTcHack x y = y
{-# INLINE happyTcHack #-}
#else
happyTcHack x y = y
#endif

-----------------------------------------------------------------------------
-- Seq-ing.  If the --strict flag is given, then Happy emits
--      happySeq = happyDoSeq
-- otherwise it emits
--      happySeq = happyDontSeq

happyDoSeq, happyDontSeq :: a -> b -> b
happyDoSeq   a b = a `Prelude.seq` b
happyDontSeq a b = b

-----------------------------------------------------------------------------
-- Don't inline any functions from the template.  GHC has a nasty habit
-- of deciding to inline happyGoto everywhere, which increases the size of
-- the generated parser quite a bit.

#if defined(HAPPY_ARRAY)
{-# NOINLINE happyDoAction #-}
{-# NOINLINE happyTable #-}
{-# NOINLINE happyCheck #-}
{-# NOINLINE happyActOffsets #-}
{-# NOINLINE happyGotoOffsets #-}
{-# NOINLINE happyDefActions #-}
#endif
{-# NOINLINE happyShift #-}
{-# NOINLINE happySpecReduce_0 #-}
{-# NOINLINE happySpecReduce_1 #-}
{-# NOINLINE happySpecReduce_2 #-}
{-# NOINLINE happySpecReduce_3 #-}
{-# NOINLINE happyReduce #-}
{-# NOINLINE happyMonadReduce #-}
{-# NOINLINE happyGoto #-}
{-# NOINLINE happyFail #-}

-- end of Happy Template.
