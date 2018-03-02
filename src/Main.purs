module Main where

import Drawable
import Prelude
import Types

import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (CONSOLE, log, logShow)
import Data.Array (foldM)
import Data.Maybe (Maybe(..))
import FRP (FRP)
import FRP.Behavior (Behavior, sample_, step)
import FRP.Event (Event, create, subscribe)
import FRP.Event.Time (interval)
import Graphics.Canvas (Arc, CANVAS, CanvasElement, Context2D, Rectangle, arc, beginPath, clearRect, closePath, getCanvasElementById, getContext2D, rect, setStrokeStyle, stroke)
import Math (pi)
import Unsafe.Coerce (unsafeCoerce)
import Utils (tree, subTree, defaultMetaData, getAnimOps)

-- | Find bound to redraw and clear the screen with that bound
-- | then draw the stateTree given to it via state behavior
-- TODO: add drawable constraint on a and typecheck
setupUpdate
  :: forall eff a
   . Drawable a
   => Context2D
   -> Behavior (StateTree a MetaData)
   -> Event (StateTree a MetaData)
   -> Eff (AllEffs eff) (Eff (AllEffs eff) Unit)
setupUpdate ctx stateB evStream =
  subscribe sampler
    \s -> clearRect ctx (rectBoundToClear (getBound s)) *> draw ctx s
      where
        rectBoundToClear {x, y, w, h} = {x: x - 2.0, y: y - 2.0, w: w + 4.0, h: h + 4.0}
        sampler = sample_ stateB evStream

-- | Run Animation operation on any StateTree
-- | and return a new updated StateTree
runOp
  :: forall a
   . Drawable a
   => StateTree a MetaData
   -> AnimationOperation
   -> StateTree a MetaData
runOp (Draw m s) (Translate x y) = Draw m (translate x y s)
runOp (Parent v lTree rTree) (Translate x y) = Parent v (translate x y lTree) (translate x y rTree)
runOp s _ = s

-- | At each event/tick of frameStream perform all animOperations
-- | Check if state changed, if changed push the new state to stateStream
animate
  :: forall a eff
   . Drawable a
   => Eq a
   => (Behavior (StateTree a MetaData))
   -> Event Int
   -> (StateTree a MetaData -> Eff (AllEffs eff) Unit)
   -> Eff (AllEffs eff) (Eff (AllEffs eff) Unit)
animate stateB frameStream push =
  let sampler = sample_ stateB frameStream
      subscriber = subscribe sampler
  in subscribe sampler onSubscribe
    where
      -- | Send new state event when state changed
      updateIfChanged newState oldState = when (not $ newState == oldState) (push newState) *> pure newState
      -- | Perform each operation and update
      onSubscribe = \s -> foldM (\state op -> updateIfChanged (runOp state op) state) s (getAnimOps s)

-- | Create stateStream - stream of events for any new state
-- | Setup update loop and animation operations loop
initCanvas :: forall e. CanvasElement -> Context2D -> Eff (Effs) Unit
initCanvas c ctx = do
  _ <- setStrokeStyle "#000000" ctx
  g <- createAnim ctx (tree [Translate 0.0 1.0, Translate 1.0 0.0]) 60
  g1 <- createAnim ctx (subTree [Translate 1.0 0.0]) 60
  pure unit

type Gref a = {
  updateCanceller :: forall e. Eff Effs Unit
  , animCanceller :: Eff Effs Unit
  , state :: Drawable a => StateTree a MetaData
}
newtype Graphic a = Graphic (Gref a)

-- Every Animation contains a state
-- has own update loop where it is really getting drawn
-- Animation loop where animation operations are done to state
-- so it has animation pipe line
createAnim
  :: forall a eff
   . Drawable a
   => Eq a
   => Context2D
   -> StateTree a MetaData
   -> Int
   -> Eff Effs (Graphic a)
createAnim ctx state frameRate = do
  {event, push} <- create
  let stateBeh = step state event
      frameInterval = 1000 / frameRate
      frameStream = interval frameInterval
  animCanceller <- animate stateBeh frameStream push
  updateCanceller <- setupUpdate ctx stateBeh event
  pure $ Graphic {animCanceller, updateCanceller, state}



main :: forall e. Eff (Effs) Unit
main = do
  maybeCanvas <- getCanvasElementById "canvas"
  case maybeCanvas of
       Just c -> getContext2D c >>= initCanvas c
       Nothing -> log "no canvas found"
