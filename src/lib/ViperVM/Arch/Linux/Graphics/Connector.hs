{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}

-- | Graphic card connector management
module ViperVM.Arch.Linux.Graphics.Connector
   ( Connector(..)
   , Connection(..)
   , SubConnectorType(..)
   , ConnectorType(..)
   , SubPixel(..)
   , connectorEncoder
   , connectorController
   , cardConnectors
   )
where

import ViperVM.Arch.Linux.Ioctl
import ViperVM.Arch.Linux.ErrorCode

import ViperVM.Arch.Linux.Graphics.Mode
import ViperVM.Arch.Linux.Graphics.Card
import ViperVM.Arch.Linux.Graphics.Encoder
import ViperVM.Arch.Linux.Graphics.Controller

import Control.Monad.IO.Class (liftIO)
import Control.Monad (liftM2)
import Control.Monad.Trans.Either
import Data.Word
import Foreign.CStorable
import Foreign.Marshal.Array (peekArray, allocaArray)
import Foreign.Ptr
import Foreign.Storable
import GHC.Generics (Generic)

-- | Connector property
data ConnectorProperty = ConnectorProperty Word32 Word64 deriving (Show)

-- | Indicate if a cable is plugged in the connector
data Connection
   = Connected          -- ^ The connector is connected to a displaying device
   | Disconnected       -- ^ The connector is disconnected
   | ConnectionUnknown  -- ^ The connection state cannot be determined
   deriving (Eq,Ord,Show)

-- | Indicate how a pixel is physically subdivised in RGB pixel elements
data SubPixel
   = SubPixelUnknown
   | SubPixelHorizontalRGB
   | SubPixelHorizontalBGR
   | SubPixelVerticalRGB
   | SubPixelVerticalBGR
   | SubPixelNone
   deriving (Eq,Ord,Enum,Show)

newtype ConnectorTypeID = ConnectorTypeID Word32 deriving (Show)

-- | A connector on the graphic card
data Connector = Connector
   { connectorPossibleEncoderIDs :: [EncoderID]          -- ^ IDs of the encoders that can work with this connector
   , connectorModes              :: [Mode]               -- ^ Supported modes
   , connectorProperties         :: [ConnectorProperty]  -- ^ Properties of the connector
   , connectorEncoderID          :: Maybe EncoderID      -- ^ Currently used encoder
   , connectorID                 :: ConnectorID          -- ^ ID
   , connectorType               :: ConnectorType        -- ^ Type of connector
   , connectorTypeID             :: ConnectorTypeID      -- ^ Identifier within connectors of the same type

   , connectorState              :: Connection           -- ^ Connection state
   , connectorWidth              :: Word32               -- ^ Width (in millimeters)
   , connectorHeight             :: Word32               -- ^ Height (in millimeters)
   , connectorSubPixel           :: SubPixel             -- ^ Sub-pixel structure
   , connectorCard               :: Card                 -- ^ Graphic card
   } deriving (Show)

-- | Get connector
cardConnectorFromID :: Card -> ConnectorID -> SysRet Connector
cardConnectorFromID card connId@(ConnectorID cid) = withCard card $ \ioctl fd -> runEitherT $ do
   let 
      res = ConnectorStruct 0 0 0 0 0 0 0 0 cid 0 0 0 0 0 0

      allocaArray' :: (Integral c, Storable a) => c -> (Ptr a -> IO b) -> IO b
      allocaArray'      = allocaArray . fromIntegral

      peekArray' :: (Storable a, Integral c) => c -> Ptr a -> IO [a]
      peekArray'        = peekArray . fromIntegral

      getModeConnector' = EitherT . ioctlReadWrite ioctl 0x64 0xA7 defaultCheck fd

   -- First we get the number of each resource
   res2 <- getModeConnector' res

   -- then we allocate arrays of appropriate sizes
   (rawRes, retRes) <-
      EitherT $ allocaArray' (connModesCount res2) $ \(ms :: Ptr ModeStruct) ->
         allocaArray' (connPropsCount res2) $ \(ps :: Ptr Word32) ->
            allocaArray' (connPropsCount res2) $ \(pvs :: Ptr Word64) ->
               allocaArray' (connEncodersCount res2) $ \(es:: Ptr Word32) -> runEitherT $ do
                  -- we put them in a new struct
                  let
                     cv = fromIntegral . ptrToWordPtr
                     res3 = res2 { connEncodersPtr   = cv es
                                 , connModesPtr      = cv ms
                                 , connPropsPtr      = cv ps
                                 , connPropValuesPtr = cv pvs
                                 }
                     isConnected x = case x of
                        1 -> Connected
                        2 -> Disconnected
                        _ -> ConnectionUnknown

                  -- we get the values
                  let wrapZero 0 = Nothing
                      wrapZero x = Just x
                  res4 <- getModeConnector' res3
                  res5 <- liftIO $ Connector
                     <$> (fmap EncoderID <$> peekArray' (connEncodersCount res2) es)
                     <*> (fmap fromModeStruct <$> peekArray' (connModesCount res2) ms)
                     <*> (liftM2 ConnectorProperty <$> peekArray' (connPropsCount res2) ps
                                                   <*> peekArray' (connPropsCount res2) pvs)
                     <*> return (EncoderID            <$> wrapZero (connEncoderID_ res4))
                     <*> return (ConnectorID           $ connConnectorID_ res4)
                     <*> return (toEnum . fromIntegral $ connConnectorType_ res4)
                     <*> return (ConnectorTypeID       $ connConnectorTypeID_ res4)
                     <*> return (isConnected           $ connConnection_ res4)
                     <*> return (connWidth_ res4)
                     <*> return (connHeight_ res4)
                     <*> return (toEnum . fromIntegral $ connSubPixel_ res4)
                     <*> return card

                  right (res4, res5)

   -- we need to check that the number of resources is still the same (as
   -- resources may have appeared between the time we get the number of
   -- resources and the time we get them...)
   -- If not, we redo the whole process
   if   connModesCount    res2 < connModesCount    rawRes
     || connPropsCount    res2 < connPropsCount    rawRes
     || connEncodersCount res2 < connEncodersCount rawRes
      then EitherT $ cardConnectorFromID card connId
      else right retRes


data SubConnectorType
   = SubConnectorAuto
   | SubConnectorUnknown
   | SubConnectorDVID
   | SubConnectorDVIA
   | SubConnectorComposite
   | SubConnectorSVIDEO
   | SubConnectorComponent
   | SubConnectorSCART
   deriving (Show)

instance Enum SubConnectorType where
   toEnum x = case x of
      0 -> SubConnectorUnknown
      3 -> SubConnectorDVID
      4 -> SubConnectorDVIA
      5 -> SubConnectorComposite
      6 -> SubConnectorSVIDEO
      8 -> SubConnectorComponent
      9 -> SubConnectorSCART
      _ -> error $ "Invalid sub-connector type (" ++ show x ++ ")"

   fromEnum x = case x of
      SubConnectorAuto        -> 0
      SubConnectorUnknown     -> 0
      SubConnectorDVID        -> 3
      SubConnectorDVIA        -> 4
      SubConnectorComposite   -> 5
      SubConnectorSVIDEO      -> 6
      SubConnectorComponent   -> 8
      SubConnectorSCART       -> 9

-- | Connector type
data ConnectorType
   = ConnectorTypeUnknown
   | ConnectorTypeVGA
   | ConnectorTypeDVII
   | ConnectorTypeDVID
   | ConnectorTypeDVIA
   | ConnectorTypeComposite
   | ConnectorTypeSVIDEO
   | ConnectorTypeLVDS
   | ConnectorTypeComponent
   | ConnectorType9PinDIN
   | ConnectorTypeDisplayPort
   | ConnectorTypeHDMIA
   | ConnectorTypeHDMIB
   | ConnectorTypeTV
   | ConnectorTypeeDP
   | ConnectorTypeVirtual
   | ConnectorTypeDSI
   deriving (Eq, Ord, Enum)

instance Show ConnectorType where
   show x = case x of
      ConnectorTypeUnknown       -> "Unknown"
      ConnectorTypeVGA           -> "VGA"
      ConnectorTypeDVII          -> "DVI-I"
      ConnectorTypeDVID          -> "DVI-D"
      ConnectorTypeDVIA          -> "DVI-A"
      ConnectorTypeComposite     -> "Composite"
      ConnectorTypeSVIDEO        -> "SVIDEO"
      ConnectorTypeLVDS          -> "LVDS"
      ConnectorTypeComponent     -> "Component"
      ConnectorType9PinDIN       -> "9PinDIN"
      ConnectorTypeDisplayPort   -> "DisplayPort"
      ConnectorTypeHDMIA         -> "HDMI-A"
      ConnectorTypeHDMIB         -> "HDMI-B"
      ConnectorTypeTV            -> "TV"
      ConnectorTypeeDP           -> "eDP"
      ConnectorTypeVirtual       -> "Virtual"
      ConnectorTypeDSI           -> "DSI"


-- | Data matching the C structure drm_mode_get_connector
data ConnectorStruct = ConnectorStruct
   { connEncodersPtr       :: Word64
   , connModesPtr          :: Word64
   , connPropsPtr          :: Word64
   , connPropValuesPtr     :: Word64

   , connModesCount        :: Word32
   , connPropsCount        :: Word32
   , connEncodersCount     :: Word32

   , connEncoderID_        :: Word32   -- ^ current encoder
   , connConnectorID_      :: Word32   -- ^ ID
   , connConnectorType_    :: Word32
   , connConnectorTypeID_  :: Word32

   , connConnection_       :: Word32
   , connWidth_            :: Word32   -- ^ HxW in millimeters
   , connHeight_           :: Word32
   , connSubPixel_         :: Word32
   } deriving Generic

instance CStorable ConnectorStruct
instance Storable ConnectorStruct where
   sizeOf      = cSizeOf
   alignment   = cAlignment
   peek        = cPeek
   poke        = cPoke

-- | Get connectors (discard errors)
cardConnectors :: Card -> IO [Connector]
cardConnectors = cardEntities cardConnectorIDs cardConnectorFromID


-- | Encoder attached to the connector, if any
connectorEncoder :: Connector -> SysRet (Maybe Encoder)
connectorEncoder conn = case connectorEncoderID conn of
   Nothing    -> return (Right Nothing)
   Just encId -> fmap Just <$> cardEncoderFromID (connectorCard conn) encId

-- | Retrieve Controller (and encoder) controling a connector (if any)
connectorController :: Connector -> SysRet (Maybe Controller, Maybe Encoder)
connectorController conn = runEitherT $ 
   EitherT (connectorEncoder conn) >>= \case
      Nothing  -> right (Nothing,Nothing)
      Just enc -> EitherT (encoderController enc) >>= \case
         Nothing   -> right (Nothing,Just enc)
         Just cont -> right (Just cont,Just enc)

