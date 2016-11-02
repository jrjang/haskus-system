{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Pipe
module ViperVM.Arch.Linux.Pipe
   ( createPipe
   )
where

import ViperVM.Arch.Linux.ErrorCode
import ViperVM.Arch.Linux.Handle
import ViperVM.Arch.Linux.Syscalls
import ViperVM.Format.Binary.Ptr
import ViperVM.Format.Binary.Storable
import ViperVM.Utils.Flow

-- | Create a pipe
createPipe :: IOErr (Handle, Handle)
createPipe =
   allocaArray 2 $ \(ptr :: Ptr Word) ->
      syscall @"pipe" (castPtr ptr)
         ||> toErrorCode
         >.~.> (const ((,)
            <$> (Handle <$> peekElemOff ptr 0)
            <*> (Handle <$> peekElemOff ptr 1)))
      
