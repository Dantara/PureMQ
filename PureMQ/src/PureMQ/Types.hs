module PureMQ.Types where

import           Data.Text    (Text)
import           GHC.Generics

newtype TransactionID = TransactionID
  { unTrasactionID :: Int }
  deriving (Eq, Ord, Show, Generic)

data TransactionError
  = WrongTransStatusChange TransStatus TransStatus
  | WrongTransStatus TransStatus
  | TransactionWasCancelled Text
  deriving (Eq, Ord, Show, Generic)

data TransStatus
  = Initiated
  | Prepared
  | Committed
  | Canceled
  deriving (Eq, Ord, Show, Generic)
