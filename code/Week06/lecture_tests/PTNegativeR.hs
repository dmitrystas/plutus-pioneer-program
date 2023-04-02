{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main where

import qualified NegativeR as OnChain
import           Plutus.V2.Ledger.Api (PubKeyHash, Value
                                      , TxOut (txOutValue), TxOutRef)
import           PlutusTx.Prelude     (($), Eq ((==)), (&&), (.), Bool, Ord ((<=)), return)
import           Prelude             (IO, mconcat, Ord ((>), (<)), Num ((-), (+)))
import           Control.Monad        (replicateM, mapM)
import           Plutus.Model         ( ada, adaValue,
                                       newUser, payToKey, payToScript, spend, spendScript, submitTx, userSpend, valueAt, toV2,
                                       utxoAt, defaultBabbage, Ada(Lovelace),
                                       DatumMode(HashDatum), UserSpend, Tx,
                                       TypedValidator(TypedValidator), runMock, initMock, Run )
import           Test.Tasty           ( defaultMain, testGroup )
import PlutusTx.Builtins (mkI, Integer)
import Test.QuickCheck
    ( (==>), collect, expectFailure, Property, Testable(property) )
import Test.Tasty.QuickCheck as QC ( testProperty )
import Test.QuickCheck.Monadic (assert, run, monadic, PropertyM)

---------------------------------------------------------------------------------------------------
--------------------------------------- TESTING MAIN ----------------------------------------------

-- | Make Run an instance of Testable so we can use it with QuickCheck
instance Testable a => Testable (Run a) where
  property rp = let (a,_) = runMock rp $ initMock defaultBabbage (adaValue 10_000_000) in property a

-- | Test the validator script
main :: IO ()
main = do
  defaultMain $ do
    testGroup
      "Testing script properties regarding redeemer values"
      [ testProperty "All values succeed" prop_successAllValues
      , testProperty "Positive redeemers fail" prop_failIfPositive
      , testProperty "Negative redeemers succeed" prop_successIfNegative
      -- , testProperty "Negative values succeed (showing tested redeemers)" prop_successIfNegative'
      ]

---------------------------------------------------------------------------------------------------
------------------------------------- HELPER FUNCTIONS --------------------------------------------

-- Set many users at once
setupUsers :: Run [PubKeyHash]
setupUsers = replicateM 2 $ newUser $ ada (Lovelace 1000)

-- Validator's script
valScript :: TypedValidator datum redeemer
valScript = TypedValidator $ toV2 OnChain.validator

-- Create transaction that spends "usp" to lock "val" in the "valScript" validator
lockingTx :: UserSpend -> Value -> Tx
lockingTx usp val =
  mconcat
    [ userSpend usp
    , payToScript valScript (HashDatum ()) val
    ]

-- Create transaction that spends "giftRef" to unlock "giftVal" from the "valScript" validator
consumingTx :: Integer -> PubKeyHash -> TxOutRef -> Value -> Tx
consumingTx redeemer usr giftRef giftVal =
  mconcat
    [ spendScript valScript giftRef (mkI redeemer) ()
    , payToKey usr giftVal
    ]
      
---------------------------------------------------------------------------------------------------
------------------------------------- TESTING VALUES ----------------------------------------------

-- | The validator should have the property that only negative values succeed
prop_successAllValues :: Integer -> Property
prop_successAllValues v = (v > 0) ==> monadic property $ checkValues v

-- | Check that the expected and real balances match after using the validator with different values
checkValues :: Integer -> PropertyM Run ()
checkValues value = do
  balancesMatch <- run $ testValue value
  assert balancesMatch

-- Function to test if both creating an consuming script UTxOs works properly 
testValue :: Integer -> Run Bool
testValue v = do
  -- SETUP USERS
  [u1, u2] <- setupUsers
  -- USER 1 LOCKS 100 ADA ("val") IN VALIDATOR
  let val = adaValue v                    -- Define value to be transfered
  sp <- spend u1 val                        -- Get user's UTXO that we should spend
  submitTx u1 $ lockingTx sp val            -- User 1 submits "lockingTx" transaction
  -- USER 2 TAKES "val" FROM VALIDATOR
  utxos <- utxoAt valScript                 -- Query blockchain to get all UTxOs at script
  let [(giftRef, giftOut)] = utxos          -- We know there is only one UTXO (the one we created before)
  submitTx u2 $ consumingTx 0 u2 giftRef (txOutValue giftOut)   -- User 2 submits "consumingTx" transaction
  -- CHECK THAT FINAL BALANCES MATCH EXPECTED BALANCES
  [v1, v2] <- mapM valueAt [u1, u2]
  return $ v1 == adaValue (1000 - v) && v2 == adaValue (1000 + v)

---------------------------------------------------------------------------------------------------
------------------------------------- TESTING REDEEMERS -------------------------------------------

-- | The validator should have the property that all positive values fail
prop_failIfPositive :: Integer -> Property
prop_failIfPositive r = (r > 0) ==> collect r . expectFailure $ monadic property $ checkRedeemers r

-- | The validator should have the property that only negative values succeed
prop_successIfNegative :: Integer -> Property
prop_successIfNegative r = (r < 0) ==> monadic property $ checkRedeemers r

-- | Same as prop_successIfNeg but collecting the redeemer value for further analysis
prop_successIfNegative' :: Integer -> Property
prop_successIfNegative' r = (r <= 0) ==> collect r $ monadic property $ checkRedeemers r

-- | Check that the expected and real balances match after using the validator with different redeemers
checkRedeemers :: Integer -> PropertyM Run ()
checkRedeemers redeemer = do
  balancesMatch <- run $ testRedeemer redeemer
  assert balancesMatch

-- Function to test if both creating an consuming script UTxOs works properly 
testRedeemer :: Integer -> Run Bool
testRedeemer r = do
  -- SETUP USERS
  [u1, u2] <- setupUsers
  -- USER 1 LOCKS 100 ADA ("val") IN VALIDATOR
  let val = adaValue 100                    -- Define value to be transfered
  sp <- spend u1 val                        -- Get user's UTXO that we should spend
  submitTx u1 $ lockingTx sp val            -- User 1 submits "lockingTx" transaction
  -- USER 2 TAKES "val" FROM VALIDATOR
  utxos <- utxoAt valScript                 -- Query blockchain to get all UTxOs at script
  let [(giftRef, giftOut)] = utxos          -- We know there is only one UTXO (the one we created before)
  submitTx u2 $ consumingTx r u2 giftRef (txOutValue giftOut)   -- User 2 submits "consumingTx" transaction
  -- CHECK THAT FINAL BALANCES MATCH EXPECTED BALANCES
  [v1, v2] <- mapM valueAt [u1, u2]
  return $ v1 == adaValue 900 && v2 == adaValue 1100
