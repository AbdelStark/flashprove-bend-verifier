import Base
import ./base_check.bend as B
import ./key_stage_codes.bend as Code
import ./transcript.bend as T
import ./opening_bytes.bend as O
import ./extension.bend as E
import ./hash_bytes.bend as H
import ./header.bend as Header

type Check is Data:
  Unused{}
  Symbols{rows: B.Rows, lambda: E.E3}

type State is Data:
  State{remaining: List<&2,Code.Final>, lambda: Maybe<&2,E.E3>}

type Step is Data:
  Step{state: State, check: Check}

def required(rows: Maybe<&2,B.Rows>, lambda: E.E3, tail: List<&2,Code.Final>) -> IO(Step):
  match rows:
    case Some{r}: IO.pure(Step,Step{State{tail,None{}},Symbols{r,lambda}})
    case None{}: IO.die(Step,1,"NO: key-base-message")

def enter(state: State, message: H.Bytes) -> IO(Step):
  match state:
    case State{Code.Final{main,mask} <> tail,Some{lambda}}: required(B.read(main,mask,message),lambda,tail)
    case _: IO.die(Step,1,"NO: key-base-schedule")

def prepare(name: String, message: H.Bytes, stream: T.Stream, state: State) -> IO(Step):
  match name state:
    case "BASE lambda" State{remaining,None{}}:
      IO.pure(Step,Step{State{remaining,Some{T.value(E.E3,T.element(stream))}},Unused{}})
    case "BASE lambda" _: IO.die(Step,1,"NO: key-base-challenge")
    case "BASE" cur: enter(cur,message)
    case _ cur: IO.pure(Step,Step{cur,Unused{}})

def check(mode: Check, places: O.Places, cols: O.Columns) -> IO(Unit):
  match mode:
    case Unused{}: IO.pure(Unit,Unit{})
    case Symbols{rows,lambda}: Header.require(B.symbols(rows,lambda,places,cols),"NO: key-base-symbol")

def complete(state: State) -> Bool:
  match state:
    case State{[],None{}}: True{}
    case _: False{}
