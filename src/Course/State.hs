{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE RebindableSyntax #-}

module Course.State where

import Course.Core
import qualified Prelude as P
import Course.Optional
import Course.List
import Course.Functor
import Course.Applicative
import Course.Monad
import qualified Data.Set as S

-- $setup
-- >>> import Test.QuickCheck.Function
-- >>> import Data.List(nub)
-- >>> import Test.QuickCheck
-- >>> import qualified Prelude as P(fmap)
-- >>> import Course.Core
-- >>> import Course.List
-- >>> instance Arbitrary a => Arbitrary (List a) where arbitrary = P.fmap listh arbitrary

-- A `State` is a function from a state value `s` to (a produced value `a`, and a resulting state `s`).
newtype State s a =
  State (
    s
    -> (a, s)
  )

runState ::
  State s a
  -> s
  -> (a, s)
runState (State f) =
  f

-- | Run the `State` seeded with `s` and retrieve the resulting state.
--
-- prop> \(Fun _ f) s -> exec (State f) s == snd (runState (State f) s)
exec ::
  State s a
  -> s
  -> s
exec (State f) s = snd (f s)


-- | Run the `State` seeded with `s` and retrieve the resulting value.
--
-- prop> \(Fun _ f) s -> eval (State f) s == fst (runState (State f) s)
eval ::
  State s a
  -> s
  -> a
eval (State f) s = fst (f s)

-- | A `State` where the state also distributes into the produced value.
--
-- >>> runState get 0
-- (0,0)
get ::
  State s s
get = State (\s -> (s, s))

-- | A `State` where the resulting state is seeded with the given value.
--
-- >>> runState (put 1) 0
-- ((),1)
put ::
  s
  -> State s ()
put s = State (\_ -> ((), s))

-- | Implement the `Functor` instance for `State s`.
--
-- >>> runState ((+1) <$> State (\s -> (9, s * 2))) 3
-- (10,6)
instance Functor (State s) where
  (<$>) ::
    (a -> b)
    -> State s a
    -> State s b
  (<$>) f initialState =
    State (\incommingState ->
      let (cv, cs) = runState initialState incommingState -- cv: computed value, cs: computed state
      in  (f cv, cs)) -- f cv: apply the function to the computed value

    -- -- run the initial state with the next state, storing the resultant value and state           
    -- let   (resultantValue, resultantState) = runState initialState nextState 

    -- -- use the function to transform the resultant value, returning the new value and state
    -- in    (someFunction resultantValue, resultantState))                     

-- | Implement the `Applicative` instance for `State s`.
--
-- >>> runState (pure 2) 0
-- (2,0)
--
-- >>> runState (pure (+1) <*> pure 0) 0
-- (1,0)
--
-- >>> runState (State (\s -> ((+3), s ++ ("apple":.Nil))) <*> State (\s -> (7, s ++ ("banana":.Nil)))) Nil
-- (10,["apple","banana"])

instance Applicative (State s) where
  pure ::
    a
    -> State s a
  pure a = State (\s -> (a, s))
  (<*>) ::
    State s (a -> b) -- this is a state where the value is a function
    -> State s a     -- this is the initial state
    -> State s b     -- this is the state resulting from unrwapping and applying the function to the initial state
  (<*>) stateWithFunction initialState = 
    
    State (\incommingState ->

    -- unwrap the function and the state by running the stateWithFunction with incomingState
    let (unwrappedFunction, intermediateState) = runState stateWithFunction incommingState 

    -- run the initialState with the intermediateState, storing the computed value and finalState
        (computedValue, finalState) = runState initialState intermediateState

    -- apply the unwrapped function to the computed value
    in  (unwrappedFunction computedValue, finalState))

-- | Implement the `Monad` instance for `State s`.
--
-- >>> runState ((const $ put 2) =<< put 1) 0
-- ((),2)
--
-- >>> let modify f = State (\s -> ((), f s)) in runState (modify (+1) >>= \() -> modify (*2)) 7
-- ((),16)
--
-- >>> runState ((\a -> State (\s -> (a + s, 10 + s))) =<< State (\s -> (s * 2, 4 + s))) 2
-- (10,16)
instance Monad (State s) where
  (=<<) ::
    (a -> State s b) -- this is a function that takes a value and returns a state
    -> State s a     -- this is the initial state
    -> State s b     -- this is the state resulting from unrwapping and applying the function to the initial state
  (=<<) functionWithState initialState =
    State (\incomingState ->

      -- destructure the initial state by running it with the incoming state
      let (computedValue, intermediateState) = runState initialState incomingState

      -- apply the function(a -> State s b) to the computed value, returning the new state
          newState = functionWithState computedValue

      -- run the new state with the intermediate state returning the final value and state
      in runState newState intermediateState)

-- | Find the first element in a `List` that satisfies a given predicate.
-- It is possible that no element is found, hence an `Optional` result.
-- However, while performing the search, we sequence some `Monad` effect through.
--
-- Note the similarity of the type signature to List#find
-- where the effect appears in every return position:
--   find ::  (a ->   Bool) -> List a ->    Optional a
--   findM :: (a -> f Bool) -> List a -> f (Optional a)
--
-- >>> let p x = (\s -> (const $ pure (x == 'c')) =<< put (1+s)) =<< get in runState (findM p $ listh ['a'..'h']) 0
-- (Full 'c',3)
--
-- >>> let p x = (\s -> (const $ pure (x == 'i')) =<< put (1+s)) =<< get in runState (findM p $ listh ['a'..'h']) 0
-- (Empty,8)
findM ::
  Monad f =>
  (a -> f Bool)
  -> List a
  -> f (Optional a)
findM monadicPredicate list = 
  foldRight 
  (\a b -> 
    (\x -> if x 
      then pure (Full a) 
      else b) =<< monadicPredicate a) 
  (pure Empty) list

-- | Find the first element in a `List` that repeats.
-- It is possible that no element repeats, hence an `Optional` result.
--
-- /Tip:/ Use `findM` and `State` with a @Data.Set#Set@.
--
-- >>> firstRepeat $ 1 :. 2 :. 0 :. 9 :. 2 :. 1 :. Nil
-- Full 2
--
-- prop> \xs -> case firstRepeat xs of Empty -> let xs' = hlist xs in nub xs' == xs'; Full x -> length (filter (== x) xs) > 1
-- prop> \xs -> case firstRepeat xs of Empty -> True; Full x -> let (l, (rx :. rs)) = span (/= x) xs in let (l2, r2) = span (/= x) rs in let l3 = hlist (l ++ (rx :. Nil) ++ l2) in nub l3 == l3
firstRepeat ::
  Ord a =>
  List a
  -> Optional a
firstRepeat list = 
  eval (findM (\a -> State (\s -> (S.member a s, S.insert a s))) list) S.empty

-- | Remove all duplicate elements in a `List`.
-- /Tip:/ Use `filtering` and `State` with a @Data.Set#Set@.
--
-- prop> \xs -> firstRepeat (distinct xs) == Empty
--
-- prop> \xs -> distinct xs == distinct (flatMap (\x -> x :. x :. Nil) xs)
distinct ::
  Ord a =>
  List a
  -> List a
distinct list = 
  eval (filtering (\a -> State (\s -> (not $ S.member a s, S.insert a s))) list) S.empty

-- | A happy number is a positive integer, where the sum of the square of its digits eventually reaches 1 after repetition.
-- In contrast, a sad number (not a happy number) is where the sum of the square of its digits never reaches 1
-- because it results in a recurring sequence.
--
-- /Tip:/ Use `firstRepeat` with `produce`.
--
-- /Tip:/ Use `join` to write a @square@ function.
--
-- /Tip:/ Use library functions: @Optional#contains@, @Data.Char#digitToInt@.
--
-- >>> isHappy 4
-- False
--
-- >>> isHappy 7
-- True
--
-- >>> isHappy 42
-- False
--
-- >>> isHappy 44
-- True
isHappy ::
  Integer
  -> Bool
isHappy n = 
  contains 1 $ firstRepeat $ produce (toInteger . sum . map (join (*) . digitToInt) . listh . show') n
  where show' = show . toInteger
