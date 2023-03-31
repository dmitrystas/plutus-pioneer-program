{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}

module Homework2 where


import           Plutus.V2.Ledger.Api (BuiltinData, POSIXTime, PubKeyHash,
                                       ScriptContext, Validator,
                                       mkValidatorScript, TxInfo, scriptContextTxInfo, txInfoValidRange, from)
import           PlutusTx             (applyCode, compile, liftCode)
import           PlutusTx.Prelude     (Bool (..), (.), (&&), ($))
import           Utilities            (wrapValidator)
import Plutus.V2.Ledger.Contexts (txSignedBy)
import Plutus.V1.Ledger.Interval (contains)

---------------------------------------------------------------------------------------------------
----------------------------------- ON-CHAIN / VALIDATOR ------------------------------------------

{-# INLINABLE mkParameterizedVestingValidator #-}
-- This should validate if the transaction has a signature from the parameterized beneficiary and the deadline has passed.
mkParameterizedVestingValidator :: PubKeyHash -> POSIXTime -> () -> ScriptContext -> PlutusTx.Prelude.Bool
mkParameterizedVestingValidator _beneficiary _deadline () _ctx = signedByBeneficiary PlutusTx.Prelude.&& deadlineHasPassed
  where
    info :: TxInfo
    info = scriptContextTxInfo _ctx

    signedByBeneficiary :: PlutusTx.Prelude.Bool
    signedByBeneficiary = txSignedBy info _beneficiary

    deadlineHasPassed :: PlutusTx.Prelude.Bool
    -- deadlineHasPassed = before _deadline $ txInfoValidRange info -- это не работает
    deadlineHasPassed = contains (from _deadline) PlutusTx.Prelude.$ txInfoValidRange info -- это работает

{-# INLINABLE  mkWrappedParameterizedVestingValidator #-}
mkWrappedParameterizedVestingValidator :: PubKeyHash -> BuiltinData -> BuiltinData -> BuiltinData -> ()
mkWrappedParameterizedVestingValidator = wrapValidator PlutusTx.Prelude.. mkParameterizedVestingValidator

validator :: PubKeyHash -> Validator
validator beneficiary = mkValidatorScript ($$(compile [|| mkWrappedParameterizedVestingValidator ||]) `applyCode` liftCode beneficiary)
