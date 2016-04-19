{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

-- | Read/write
module ViperVM.Arch.Linux.FileSystem.ReadWrite
   ( IOVec(..)
   , sysRead
   , sysReadWithOffset
   , sysReadMany
   , sysReadManyWithOffset
   , sysWrite
   , sysWriteWithOffset
   , sysWriteMany
   , sysWriteManyWithOffset
   , readByteString
   , writeByteString
   )
where

import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString.Unsafe
import Data.Word (Word64, Word32)
import Foreign.CStorable
import Foreign.Marshal.Alloc
import Foreign.Marshal.Array (withArray)
import Foreign.Ptr (Ptr, castPtr, plusPtr)
import Foreign.Storable (Storable, peek, poke, sizeOf, alignment)

import GHC.Generics (Generic)

import ViperVM.Arch.Linux.ErrorCode
import ViperVM.Arch.Linux.Handle
import ViperVM.Arch.Linux.Syscalls
import ViperVM.Utils.Flow


-- | Entry for vectors of buffers
data IOVec = IOVec
   { iovecPtr  :: Ptr ()
   , iovecSize :: Word64
   } deriving (Generic,CStorable)

instance Storable IOVec where
   sizeOf      = cSizeOf
   alignment   = cAlignment
   poke        = cPoke
   peek        = cPeek

-- | Read cound bytes from the given file descriptor and put them in "buf"
-- Returns the number of bytes read or 0 if end of file
sysRead :: Handle -> Ptr a -> Word64 -> SysRet Word64
sysRead (Handle fd) buf count =
   onSuccess (syscall_read fd buf count) fromIntegral

-- | Read a file descriptor at a given position
sysReadWithOffset :: Handle -> Word64 -> Ptr () -> Word64 -> SysRet Word64
sysReadWithOffset (Handle fd) offset buf count =
   onSuccess (syscall_pread64 fd buf count offset) fromIntegral

-- | Like read but uses several buffers
sysReadMany :: Handle -> [(Ptr a, Word64)] -> SysRet Word64
sysReadMany (Handle fd) bufs =
   let
      toVec (p,s) = IOVec (castPtr p) s
      count = length bufs
   in
   withArray (fmap toVec bufs) $ \bufs' ->
      onSuccess (syscall_readv fd bufs' count) fromIntegral

-- | Like readMany, with additional offset in file
sysReadManyWithOffset :: Handle -> Word64 -> [(Ptr a, Word64)] -> SysRet Word64
sysReadManyWithOffset (Handle fd) offset bufs =
   let
      toVec (p,s) = IOVec (castPtr p) s
      count = length bufs
      -- offset is split in 32-bit words
      ol = fromIntegral offset :: Word32
      oh = fromIntegral (offset `shiftR` 32) :: Word32
   in
   withArray (fmap toVec bufs) $ \bufs' ->
      onSuccess (syscall_preadv fd bufs' count ol oh) fromIntegral

-- | Write cound bytes into the given file descriptor from "buf"
-- Returns the number of bytes written (0 indicates that nothing was written)
sysWrite :: Handle -> Ptr a -> Word64 -> SysRet Word64
sysWrite (Handle fd) buf count =
   onSuccess (syscall_write fd buf count) fromIntegral

-- | Write a file descriptor at a given position
sysWriteWithOffset :: Handle -> Word64 -> Ptr () -> Word64 -> SysRet Word64
sysWriteWithOffset (Handle fd) offset buf count =
   onSuccess (syscall_pwrite64 fd buf count offset) fromIntegral


-- | Like write but uses several buffers
sysWriteMany :: Handle -> [(Ptr a, Word64)] -> SysRet Word64
sysWriteMany (Handle fd) bufs =
   let
      toVec (p,s) = IOVec (castPtr p) s
      count = length bufs
   in
   withArray (fmap toVec bufs) $ \bufs' ->
      onSuccess (syscall_writev fd bufs' count) fromIntegral

-- | Like writeMany, with additional offset in file
sysWriteManyWithOffset :: Handle -> Word64 -> [(Ptr a, Word64)] -> SysRet Word64
sysWriteManyWithOffset (Handle fd) offset bufs =
   let
      toVec (p,s) = IOVec (castPtr p) s
      count = length bufs
      -- offset is split in 32-bit words
      ol = fromIntegral offset :: Word32
      oh = fromIntegral (offset `shiftR` 32) :: Word32
   in
   withArray (fmap toVec bufs) $ \bufs' ->
      onSuccess (syscall_pwritev fd bufs' count ol oh) fromIntegral

-- | Read n bytes in a bytestring
readByteString :: Handle -> Int -> SysRet ByteString
readByteString fd size = do
   b <- mallocBytes size
   sysRead fd b (fromIntegral size)
      -- free the pointer on error
      >..~=> const (free b)
      -- otherwise return the bytestring
      >.~.> \sz -> unsafePackCStringLen (castPtr b, fromIntegral sz)

-- | Write a bytestring
writeByteString :: Handle -> ByteString -> SysRet ()
writeByteString fd bs = unsafeUseAsCStringLen bs go
   where
      go (_,0)     = flowRet ()
      go (ptr,len) = sysWrite fd ptr (fromIntegral len)
         >.~#> \c -> go ( ptr `plusPtr` fromIntegral c
                        , len - fromIntegral c)
