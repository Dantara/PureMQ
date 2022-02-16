module PureMQ.Types where

import           Data.Text     (Text)
import           GHC.Exception
import           GHC.Generics

newtype TransactionID = TransactionID
  { unTrasactionID :: Int }
  deriving (Eq, Ord, Show, Generic, Bounded, Enum, Num)

data TransactionError
  = WrongTransStatusChange TransStatus TransStatus
  | WrongTransStatus TransStatus
  | TransactionWasCancelled Text
  | TransactionWasNotFound TransactionID
  deriving (Eq, Ord, Show, Generic)

instance Exception TransactionError

data TransStatus
  = Initiated
  | Prepared
  | Committed
  | Canceled
  deriving (Eq, Ord, Show, Generic)

data IsolationLevel
  = ReadCommitted
  | Serializable
  deriving (Eq, Ord, Show, Generic)

data NoKey -- Specialized alternative for Data.Void

data PreparedTransaction a = PreparedTransaction
  { transactionId :: TransactionID
  , result        :: a }
  deriving (Generic)

class StorageEff (e :: (* -> *) -> * -> *)
