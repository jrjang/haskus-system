-- | X86 Archtiectures and micro-architectures
module ViperVM.Arch.X86_64.MicroArch
   ( X86Arch(..)
   )
where

-- | X86 micro-architecture
data X86Arch
   = Intel486
   | IntelPentium
   | IntelP6
   deriving (Show,Eq)

