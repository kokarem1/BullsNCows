module Main

import Effects
import Effect.System
import Effect.StdIO
import Effect.Random
import Data.So
import Data.Fin
import Data.Vect

-----------------------------------------------------------------------
-- GAME STATE
-----------------------------------------------------------------------

data GState = Running Nat Nat | NotRunning

data BullsNCows : GState -> Type where
     Init     : BullsNCows NotRunning -- initialising, but not ready
     GameWon  : String -> BullsNCows NotRunning
     GameLost : String -> BullsNCows NotRunning
     MkG      : (word : String) ->
                (gue: List Char) ->
                (guesses : Nat) ->
                (got : List Char) ->
                (missing : Vect m Char) ->
                BullsNCows (Running guesses m)

instance Default (BullsNCows NotRunning) where
    default = Init

instance Show (BullsNCows s) where
    show Init = "Not ready yet"
    show (GameWon w) = "You won! Successfully guessed " ++ w
    show (GameLost w) = "You lost! The word was " ++ w
    show (MkG w gue guesses got missing)
         = let w' = pack (map showGot (unpack w)) in
               w' ++ "\n\n" ++ show guesses ++ " guesses left"
      where showGot : Char -> Char
            showGot ' ' = '/'
            showGot c = if ((not (isAlpha c)) || (c `elem` got)) then c else '-'

total
letters : String -> List Char
letters x with (strM x)
  letters "" | StrNil = []
  letters (strCons y xs) | (StrCons y xs) 
          = let xs' = assert_total (letters xs) in
                if ((not (isAlpha y)) || (y `elem` xs')) then xs' else y :: xs'

initState : (x : String) -> (g : List Char) -> BullsNCows (Running 6 (length (letters x)))
initState w g = let xs = letters w in
                    MkG w g _ [] (fromList (letters w))

-----------------------------------------------------------------------
-- RULES
-----------------------------------------------------------------------

data BullsNCowsRules : Effect where

     Guess : sig BullsNCowsRules Bool
                 (BullsNCows (Running (S g) (S w)))
                 (\inword =>
                        BullsNCows (case inword of
                             True => (Running (S g) w)
                             False => (Running g (S w))))

     Won  : sig BullsNCowsRules ()
                (BullsNCows (Running g 0))
                (BullsNCows NotRunning)

     Lost : sig BullsNCowsRules ()
                (BullsNCows (Running 0 g))
                (BullsNCows NotRunning)

     NewWord : (w : String) ->
               (g: List Char) ->
               sig BullsNCowsRules () h (BullsNCows (Running 6 (length (letters w))))

     Get  : sig BullsNCowsRules h h

BULLSNCOWS : GState -> EFFECT
BULLSNCOWS h = MkEff (BullsNCows h) BullsNCowsRules

guess : Eff Bool
        [BULLSNCOWS (Running (S g) (S w))]
        (\inword => [BULLSNCOWS (case inword of
                                True => Running (S g) w
                                False => Running g (S w))])
guess = call (Main.Guess)

won :  Eff () [BULLSNCOWS (Running g 0)] [BULLSNCOWS NotRunning]
won = call Won

lost : Eff () [BULLSNCOWS (Running 0 g)] [BULLSNCOWS NotRunning]
lost = call Lost

new_word : (w : String) -> (g : List Char) -> Eff () [BULLSNCOWS h] 
                                           [BULLSNCOWS (Running 6 (length (letters w)))]
new_word w g = call (NewWord w g)

get : Eff (BullsNCows h) [BULLSNCOWS h]
get = call Get

-----------------------------------------------------------------------
-- SHRINK
-----------------------------------------------------------------------

instance Uninhabited (Elem x []) where
    uninhabited Here impossible

shrink : (xs : Vect (S n) a) -> Elem x xs -> Vect n a
shrink (x :: ys) Here = ys
shrink (y :: []) (There p) = absurd p
shrink (y :: (x :: xs)) (There p) = y :: shrink (x :: xs) p

-----------------------------------------------------------------------
-- IMPLEMENTATION OF THE RULES
-----------------------------------------------------------------------

instance Handler BullsNCowsRules m where
    handle (MkG w gue g got []) Won k = k () (GameWon w)
    handle (MkG w gue Z got m) Lost k = k () (GameLost w)

    handle st Get k = k st st
    handle st (NewWord w g) k = k () (initState w g)

    handle (MkG w gue (S g) got m) (Guess) k =
      case nonEmpty gue of
           Yes _ => let x = head gue in
                        case isElem x m of
                             No _ => k False (MkG w (tail gue) _ got m)
                             Yes p => k True (MkG w (tail gue) _ (x :: got) (shrink m p))
           No _ => k False (MkG w gue _ got m)

-----------------------------------------------------------------------
-- USER INTERFACE 
-----------------------------------------------------------------------

soRefl : So x -> (x = True)
soRefl Oh = Refl 

game : Eff () [BULLSNCOWS (Running (S g) w), STDIO]
              [BULLSNCOWS NotRunning, STDIO]
game {w=Z} = won 
game {w=S _}
     = do putStrLn (show !get)
          putStr "Enter guess: "
          processGuess
  where 
    processGuess : Eff () [BULLSNCOWS (Running (S g) (S w)), STDIO] 
                          [BULLSNCOWS NotRunning, STDIO] 
    processGuess {g} {w}
      = case !(guess) of
             True => do putStrLn "Good guess!"
                        case w of
                             Z => won
                             (S k) => game
             False => do putStrLn "No, sorry"
                         case g of
                              Z => lost
                              (S k) => game

words : ?wlen 
words = with Vect ["idris","agda","haskell","miranda",
         "java","javascript","fortran","basic","racket",
         "coffeescript","rust","purescript","clean","links",
         "koka","cobol"]

wlen = proof search

runGame : Eff () [BULLSNCOWS NotRunning, RND, SYSTEM, STDIO]
runGame = do srand !time
             let word = !getStr
             let try_word = unpack !getStr
             new_word word try_word
             game
             putStrLn (show !get)

main : IO ()
main = run runGame

