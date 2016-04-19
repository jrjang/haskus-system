-- | Bit operations
module ViperVM.Format.Binary.BitOps
   ( makeMask
   , maskLeastBits
   , bitOffset
   , byteOffset
   , reverseBitsGeneric
   , reverseLeastBits
   , bitsToString
   , bitsFromString
   , BitReversable (..)
   , getBitRange
   )
where

import Data.Word
import Data.Bits
import Data.List (foldl')

import ViperVM.Format.Binary.BitOps.BitReverse
import ViperVM.Format.Binary.BitOrder

-- | makeMask 3 = 00000111
makeMask :: (FiniteBits a) => Word -> a
makeMask n = x' `shiftR` (finiteBitSize x - fromIntegral n)
   where
      x = complement zeroBits
      x' = if isSigned x 
               then error "Cannot use makeMask with a signed type"
               else x
{-# SPECIALIZE makeMask :: Word -> Int #-}
{-# SPECIALIZE makeMask :: Word -> Word #-}
{-# SPECIALIZE makeMask :: Word -> Word8 #-}
{-# SPECIALIZE makeMask :: Word -> Word16 #-}
{-# SPECIALIZE makeMask :: Word -> Word32 #-}
{-# SPECIALIZE makeMask :: Word -> Word64 #-}

-- | Keep only the n least-significant bits of the given value
maskLeastBits :: (FiniteBits a) => Word -> a -> a
maskLeastBits n v = v .&. makeMask n
{-# INLINE maskLeastBits #-}

-- | Compute bit offset (equivalent to x `mod` 8 but faster)
bitOffset :: Word -> Word
bitOffset n = makeMask 3 .&. n
{-# INLINE bitOffset #-}

-- | Compute byte offset (equivalent to x `div` 8 but faster)
byteOffset :: Word -> Word
byteOffset n = n `shiftR` 3
{-# INLINE byteOffset #-}

-- | Reverse the @n@ least important bits of the given value. The higher bits
-- are set to 0.
reverseLeastBits :: (FiniteBits a, BitReversable a) => Word -> a -> a
reverseLeastBits n value = reverseBits value `shiftR` (finiteBitSize value - fromIntegral n)

-- | Convert bits into a string composed of '0' and '1' chars
bitsToString :: FiniteBits a => a -> String
bitsToString x = fmap b [s, s-1 .. 0]
   where
      s   = finiteBitSize x - 1
      b v = if testBit x v then '1' else '0'

-- | Convert a string of '0' and '1' chars into a word
bitsFromString :: Bits a => String -> a
bitsFromString xs = foldl' b zeroBits (reverse xs `zip` [0..])
   where
      b x ('0',i) = clearBit x i
      b x ('1',i) = setBit x i
      b _ (c,_)   = error $ "Invalid character in the string: " ++ [c]


-- | Reverse bits in a Word
reverseBitsGeneric :: (FiniteBits a, Integral a) => a -> a
reverseBitsGeneric = liftReverseBits reverseBits4Ops

-- | Data whose bits can be reversed
class BitReversable w where
   reverseBits :: w -> w

instance BitReversable Word8 where
   reverseBits = reverseBits4Ops

instance BitReversable Word16 where
   reverseBits = reverseBits5LgN

instance BitReversable Word32 where
   reverseBits = reverseBits5LgN

instance BitReversable Word64 where
   reverseBits = reverseBits5LgN

instance BitReversable Word where
   reverseBits = reverseBits5LgN



-- | Take n bits at offset o and put them in the least-significant
-- bits of the result
getBitRange :: (BitReversable b, FiniteBits b) => BitOrder -> Word -> Word -> b -> b
getBitRange bo o n c = case bo of
      BB -> maskLeastBits n $ c             `shiftR` d
      BL -> maskLeastBits n $ reverseBits c `shiftR` o'
      LB -> maskLeastBits n $ reverseBits c `shiftR` d
      LL -> maskLeastBits n $ c             `shiftR` o'
   where 
      o' = fromIntegral o
      d  = finiteBitSize c - fromIntegral n - fromIntegral o

{-# INLINE getBitRange #-}
