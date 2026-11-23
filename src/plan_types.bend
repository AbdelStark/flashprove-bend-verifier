import Base

type Profile is Data:
  SmallExact{}
  SmallClipped{}
  FullExact{}
  FullClipped{}

type Chain is Data:
  KeyOnce{}
  KeyShared{}
  KeySecond{}
  Entry{}
  RequestFirst{}
  RequestShared{}
  RequestSecond{}

type Pin is Data:
  Pin{size: U32, entries: U32, words: List<&2, U32>}

def folder(profile: Profile) -> String:
  match profile:
    case SmallExact{}: "accepted-proof"
    case SmallClipped{}: "accepted-proof-clipped-gap"
    case FullExact{}: "full-size"
    case FullClipped{}: "full-size-clipped-gap"

def stem(chain: Chain) -> String:
  match chain:
    case KeyOnce{}: "key.one-time"
    case KeyShared{}: "key.shared"
    case KeySecond{}: "key.second"
    case Entry{}: "entry"
    case RequestFirst{}: "proof.first"
    case RequestShared{}: "proof.shared"
    case RequestSecond{}: "proof.second"
