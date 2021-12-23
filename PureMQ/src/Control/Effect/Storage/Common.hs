module Control.Effect.Storage.Common where

import           Data.Text
import           GHC.Generics

newtype TableName = TableName
  { unwrapTableName :: Text }
  deriving (Eq, Ord, Show, Generic)

data Database = Database

class StorageEff (e :: (* -> *) -> * -> *)