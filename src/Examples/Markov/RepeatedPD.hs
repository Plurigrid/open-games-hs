{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE FlexibleContexts #-}

module Examples.Markov.RepeatedPD where

import           Debug.Trace
import           Engine.Engine
import           Preprocessor.Preprocessor
import           Examples.SimultaneousMoves (ActionPD(..),prisonersDilemmaMatrix)

import           Control.Monad.State  hiding (state,void)
import qualified Control.Monad.State  as ST

import Numeric.Probability.Distribution.Observable hiding (map, lift, filter)

prisonersDilemma  :: OpenGame
                              StochasticStatefulOptic
                              StochasticStatefulContext
                              ('[Kleisli Stochastic (ActionPD, ActionPD) ActionPD,
                                 Kleisli Stochastic (ActionPD, ActionPD) ActionPD])
                              ('[[DiagnosticInfoBayesian (ActionPD, ActionPD) ActionPD],
                                 [DiagnosticInfoBayesian (ActionPD, ActionPD) ActionPD]])
                              (ActionPD, ActionPD)
                              ()
                              (ActionPD, ActionPD)
                              ()
discountFactor = 0.9

prisonersDilemma = [opengame|

   inputs    : (dec1Old,dec2Old) ;
   feedback  :      ;

   :----------------------------:
   inputs    :  (dec1Old,dec2Old)    ;
   feedback  :      ;
   operation : dependentDecision "player1" (const [Cooperate,Defect]);
   outputs   : decisionPlayer1 ;
   returns   : prisonersDilemmaMatrix decisionPlayer1 decisionPlayer2 ;

   inputs    :   (dec1Old,dec2Old)   ;
   feedback  :      ;
   operation : dependentDecision "player2" (const [Cooperate,Defect]);
   outputs   : decisionPlayer2 ;
   returns   : prisonersDilemmaMatrix decisionPlayer2 decisionPlayer1 ;

   operation : discount "player1" (\x -> x * discountFactor) ;

   operation : discount "player2" (\x -> x * discountFactor) ;

   :----------------------------:

   outputs   : (decisionPlayer1,decisionPlayer2)     ;
   returns   :      ;
  |]



-- Add strategy for stage game
stageStrategy :: Kleisli Stochastic (ActionPD, ActionPD) ActionPD
stageStrategy = Kleisli $
   (\case
       (Cooperate,Cooperate) -> playDeterministically Cooperate
       (_,_)         -> playDeterministically Defect)
-- Stage strategy tuple
strategyTuple = stageStrategy ::- stageStrategy ::- Nil

stageStrategy' :: Kleisli Stochastic (ActionPD, ActionPD) ActionPD
stageStrategy' = Kleisli $
   (\case
       (Cooperate,Cooperate) -> uniformDist [Cooperate,Defect]
       (_,_)         -> uniformDist [Cooperate,Defect])
-- Stage strategy tuple
strategyTuple' = stageStrategy ::- stageStrategy ::- Nil



-- extract continuation
extractContinuation :: StochasticStatefulOptic s () a () -> s -> StateT Vector Stochastic ()
extractContinuation (StochasticStatefulOptic v u) x = do
  (z,a) <- ST.lift (v x)
  u z ()

-- extract next state (action)
extractNextState :: StochasticStatefulOptic s () a () -> s -> Stochastic a
extractNextState (StochasticStatefulOptic v _) x = do
  (z,a) <- v x
  pure a

executeStrat strat =  play prisonersDilemma strat


-- determine continuation for iterator, with the same repeated strategy
determineContinuationPayoffs__ :: Integer
                             -> List
                                      '[Kleisli Stochastic (ActionPD, ActionPD) ActionPD,
                                        Kleisli Stochastic (ActionPD, ActionPD) ActionPD]
                             -> (ActionPD,ActionPD)
                             -> StateT Vector Stochastic ()
determineContinuationPayoffs__ 1        strat action = pure ()
determineContinuationPayoffs__ iterator strat action = do
   extractContinuation executeStrat action
   nextInput <- ST.lift $ extractNextState executeStrat action
   determineContinuationPayoffs__ (pred iterator) strat nextInput
 where executeStrat =  play prisonersDilemma strat


-- Random prior indpendent of previous moves
determineContinuationPayoffs  iterator strat action = do
  ST.lift $ note "determineContinuationPayoffs"
  go  iterator strat action
  where
    go  1 strat action = ST.lift $ note "go[1]"
    go  iterator strat action = do
      ST.lift $ note ("go[" ++ show iterator ++ "]")
      extractContinuation executeStrat action
      ST.lift $ note "nextState"
      nextInput <- ST.lift $ extractNextState executeStrat action
      go (pred iterator) strat nextInput
      where
        executeStrat = play prisonersDilemma strat



-- fix context used for the evaluation
contextCont iterator strat initialAction = StochasticStatefulContext (pure ((),initialAction)) (\_ action -> determineContinuationPayoffs iterator strat action)



repeatedPDEq iterator strat initialAction = evaluate prisonersDilemma strat context
  where context  = contextCont iterator strat initialAction





eqOutput iterator strat initialAction = generateIsEq $ repeatedPDEq iterator strat initialAction


testEq iterator = eqOutput iterator strategyTuple (Cooperate,Cooperate)

testEq' iterator = eqOutput iterator strategyTuple' (Cooperate,Cooperate)
