-- | A bit set: use bitwise operations and minimal storage
--
-- Similar to Data.Bitset.Generic from bitset package, but
--    * We don't have the Num constraint
--    * We dont use the deprecated bitSize function
--    * We use countTrailingZeros instead of iterating on the
--    number of bits
--    * We add a typeclass EnumBitSet
module ViperVM.Utils.EnumSet
   ( EnumSet (..)
   , EnumBitSet (..)
   , getBits
   , member
   , notMember
   , elems
   , toList
   , fromList
   )
where

import Data.Bits
import Data.Foldable (foldl')

myCountTrailingZeros :: (FiniteBits b) => b -> Maybe Int
myCountTrailingZeros x = 
   if x == zeroBits
      then Nothing
      else Just (countTrailingZeros x)

-- | A bit set: use bitwise operations (fast!) and minimal storage (sizeOf basetype)
--
-- b is the base type (Bits b)
-- a is the element type (Enum a)
newtype EnumSet b a = EnumSet b deriving (Show,Eq,Ord)

-- | Unwrap the bitset
getBits :: EnumSet b a -> b
getBits (EnumSet b) = b

-- | Test if an element is in the set
member :: (Bits b, Enum a) => EnumSet b a -> a -> Bool
member (EnumSet b) e = testBit b (fromEnum e)

-- | Test if an element is not in the set
notMember :: (Bits b, Enum a) => EnumSet b a -> a -> Bool
notMember b e = not (member b e)

-- | Retrieve elements in the set
elems :: (Enum a, FiniteBits b) => EnumSet b a -> [a]
elems (EnumSet b) = go b
   where
      go c = case myCountTrailingZeros c of
         Nothing -> []
         Just e  -> toEnum e : go (clearBit c e)

-- | Convert a set into a list
toList :: (Enum a, FiniteBits b) => EnumSet b a -> [a]
toList = elems

-- | Convert a Foldable into a set
fromList :: (Enum a, Bits b, Foldable m) => m a -> EnumSet b a
fromList = EnumSet . foldl' f zeroBits
   where
      f bs a = setBit bs (fromEnum a)

class Enum a => EnumBitSet a where
   -- | Convert a list of enum elements into a bitset Warning: b
   -- must have enough bits to store the given elements! (we don't
   -- perform any check, for performance reason)
   toBitSet :: (Bits b, Foldable m) => m a -> b
   toBitSet = getBits . fromList

   -- | Convert a bitset into a list of Enum elements
   fromBitSet :: (FiniteBits b) => b -> [a]
   fromBitSet = toList . EnumSet
