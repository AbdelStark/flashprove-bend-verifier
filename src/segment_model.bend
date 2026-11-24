import Base
import ./outer_source.bend as O
import ./u3_series.bend as U
import ./extension.bend as X
import ./fold.bend as F
import ./key_stage_lookup_rows.bend as L
import ./key_stage_trace.bend as Trace
import ./segment_forest.bend as Forest
import ./segment_tables.bend as Types
import ./policy_statement.bend as S

# Equations in the logical R13.4 array layout. Factor coordinates index the
# power-of-two envelope of the array, low row bits then high column bits.
type Read is Data:
  Read{owner: Nat, array: String, form: F.Form}
  U3Run{owner: Nat, series: U.Series}
  OuterRead{owner: Nat,array: String,source: O.Source}

type Aff is Data:
  Aff{terms: List<&2,Read>, masks: L.Masks, target: X.E3}

def Equations() -> Data: List<&2,Aff>

type Inputs is Data:
  Inputs{link: Nat, primary: Forest.Claims, digits: Forest.Claims, events: Trace.Events, statement: S.Statement, primary_shape: Types.Forest, digit_shape: Types.Forest}

# A U3 functional over successive length-row segments of the local matrix mu.
# Its exposed entries start at offset, one for each column and row segment.
type Functional is Data:
  Functional{matrix: Nat, length: Nat, phi: F.Form, offset: Nat}

def Functionals() -> Data: List<&2,Functional>

def mask_only(rows: List<&2,L.Row>) -> Equations:
  match rows:
    case L.Row{[],m,v} <> tail: Aff{[],m,v} <> mask_only(tail)
    case _: []

def mask_rows(forest: Forest.Claims) -> Equations:
  Forest.Claims{_,_,_,rows} = forest
  mask_only(rows)
