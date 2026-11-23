import Base
import ./plan.bend as P
import ./key_stage_geometry.bend as G
import ./opening_bytes.bend as O
import ./transcript.bend as T
import ./hash_bytes.bend as H

type Opening is Data:
  Opening{tree: G.Tree, columns: O.Columns}

def Openings() -> Data:
  List<&2,Opening>

type Observed is Data:
  Observed{round: P.Round, message: H.Bytes, stream: T.Stream, positions: O.Places, openings: Openings}

def Events() -> Data:
  List<&2,Observed>
