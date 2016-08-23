{-# LANGUAGE LambdaCase #-}

module ViperVM.Apps.Disassembler
   ( disassX86_64
   )
where


import qualified ViperVM.Format.Text as Text
import ViperVM.Format.Text (Text)
import ViperVM.Format.Binary.Buffer
import qualified ViperVM.Format.Binary.BitSet as BitSet
import ViperVM.Arch.X86_64.ISA.Mode
import ViperVM.Arch.X86_64.ISA.Size
import ViperVM.Arch.X86_64.ISA.Decoder
import ViperVM.Arch.X86_64.ISA.Insn
import ViperVM.Arch.X86_64.ISA.Encoding
import ViperVM.Arch.X86_64.ISA.Registers
import ViperVM.Arch.X86_64.Disassembler

import Data.Text.Lazy.Builder
import qualified Data.Text.Lazy as LT
import Data.Maybe
import Data.List

-- | Disassemble a buffer containing X86-64 assembly.
-- Enable all the extensions
disassX86_64 :: Buffer -> Text
disassX86_64 buffer = LT.toStrict (toLazyText bld)
   where
      -- disassembled buffer
      ds = linearDisass m buffer


      -- arch mode
      m = ExecMode
            { x86Mode            = LongMode Long64bitMode
            , defaultAddressSize = AddrSize64
            , defaultOperandSize = OpSize32
            , extensions         = allExtensions
            }

      -- builder
      bld = mconcat (fmap (fromText . showDisass) ds)


      -- show an instruction
      showInsn o b cmt = Text.pack str
         where
            o'     = show o
            b'     = show b
            fill c = replicate c ' '
            str = o'
                  ++ fill (10 - fromIntegral (length o'))
                  ++ b'
                  ++ fill (30 - fromIntegral (length b'))
                  ++ cmt
                  ++ "\n"

      -- show a disassembled entry
      showDisass = \case
         RawBytes    offset buf _   -> showInsn offset buf "; raw bytes"
         Instruction offset buf ins -> showInsn offset buf $
            (if not (BitSet.null (insnVariant ins))
               then show (BitSet.toList (insnVariant ins)) ++ " "
               else ""
            )
            ++ insnMnemonic (insnSpec ins)
            ++ " "
            ++ concat (intersperse ", " (fmap showAsmOperand (insnOperands ins)))

showAsmOperand :: Operand -> String
showAsmOperand op = case op of
   OpImmediate v      -> showAsmImm v
   OpReg reg          -> showAsmReg reg
   OpRegPair r1 r2    -> showAsmReg r1 ++ ":" ++ showAsmReg r2
   OpMem _ addr       -> showAsmAddr addr -- TODO: show memory type
   OpCodeAddr addr    -> showAsmAddr addr
   OpPtr16_16 w1 w2   -> show w1 ++ ":" ++ show w2
   OpPtr16_32 w1 w2   -> show w1 ++ ":" ++ show w2
   OpStackFrame w1 w2 -> show w1 ++ ":" ++ show w2

showAsmAddr :: Addr -> String
showAsmAddr a = showAsmReg (addrSeg a) ++ ":[" ++ xs ++ "]"
   where
      xs = concat (intersperse " + " (catMaybes [bs, is, ds]))
      bs = showAsmReg <$> addrBase a
      is = case (addrIndex a, addrScale a) of
         (Nothing, _)          -> Nothing
         (Just i, Just Scale1) -> Just (showAsmReg i)
         (Just i, Nothing)     -> Just (showAsmReg i)
         (Just i, Just Scale2) -> Just (showAsmReg i >> "*2")
         (Just i, Just Scale4) -> Just (showAsmReg i >> "*4")
         (Just i, Just Scale8) -> Just (showAsmReg i >> "*8")
      ds = showAsmImm <$> addrDisp a

showAsmImm :: SizedValue -> String
showAsmImm = \case
   SizedValue8  w -> show w
   SizedValue16 w -> show w
   SizedValue32 w -> show w
   SizedValue64 w -> show w

showAsmReg :: Register -> String
showAsmReg reg = registerName reg
