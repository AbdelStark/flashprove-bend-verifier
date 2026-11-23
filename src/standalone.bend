import Base
import ./policy_statement.bend as S
import ./policy_config.bend as Config
import ./commitment.bend as Commitment
import ./header.bend as Header
import ./key_stage.bend as Key
import ./leaf_stage.bend as Leaf
import ./leaf_check.bend as Link
import ./request_stage.bend as Req
import ./hash_bytes.bend as H
import ./opening_bytes.bend as O

type Options is Data:
  Options{id: Maybe<&2,String>, policy: Maybe<&2,String>, public: Maybe<&2,String>}

def options(args: List<String>, opt: Options) -> Maybe<&2,Options>:
  match args opt:
    case Nil{} final: Some{final}
    case "-id" <> id <> tail Options{None{},p,d}: options(tail,Options{Some{id},p,d})
    case "-policy" <> policy <> tail Options{i,None{},d}: options(tail,Options{i,Some{policy},d})
    case "-data" <> folder <> tail Options{i,p,None{}}: options(tail,Options{i,p,Some{folder}})
    case "-q" <> tail state: options(tail,state)
    case _ _: None{}

type Call is Data:
  Call{ivk: String, proof: String, expected: String, plans: String, cfg: Config.Configured, statement: S.Statement}

def digest(cfg: Config.Configured) -> H.Bytes:
  Config.Configured{value,_} = cfg
  value

def request(checked: Link.Checked, +call: Call, copy: U32) -> IO(Unit):
  Link.Checked{leaf,session,_} = checked
  Call{_,proof,_,plans,cfg,st} = call
  do IO<Unit>:
    evidence : Req.Trace <- Req.inspect(proof,copy,st,cfg,plans,leaf,session)
    # Only a complete check of the request relation may issue an inference verdict.
    IO.die(Unit,3,"STAGES CHECKED: request equations incomplete")

def entry(key: Key.AttestedKey, +call: Call) -> IO(Unit):
  Key.AttestedKey{+root,+record,_,_,_,session} = key
  Call{ivk,proof,expected,plans,+cfg,st} = call
  +hash = digest(cfg)
  do IO<Unit>:
    id : String <- Commitment.from_record(Config.key_shape(st),O.digest_bytes(root),record,hash)
    named : Unit <- Header.require(String.eq(id,String.to_lower(expected)),"NO: model-statement")
    head : H.Bytes <- Header.bytes(proof,12)
    +copy : U32 <- Header.leaf_index(head)
    trace : Leaf.Trace <- Leaf.inspect(ivk ++ "/leaf/" ++ U32.show(copy) ++ ".bin",hash,plans,Leaf.Table{root,record},session)
    link : Link.Checked <- Link.algebra(trace,hash)
    request(link,call,copy)

def run(+config: String, +ivk: String, req: String, y: String, proof: String, opt: Maybe<&2,Options>) -> IO(Unit):
  match opt:
    case Some{Options{Some{id},policy,dir}}:
      +public = Maybe.default(&2,String,dir,"build")
      +plans = public ++ "/plans"
      do IO<Unit>:
        +st : S.Statement <- S.load(config,req,y,public ++ "/tables",policy)
        +cfg : Config.Configured <- Config.load(st,config,plans)
        key : Key.AttestedKey <- Key.check_transcript(ivk ++ "/key.bin",digest(cfg),plans)
        entry(key,Call{ivk,proof,id,plans,cfg,st})
    case _: IO.die(Unit,2,"usage: verify-bend CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-data DIR] [-q]")

def argv(args: List<String>) -> IO(Unit):
  match args:
    case _ <> config <> ivk <> req <> y <> proof <> tail:
      run(config,ivk,req,y,proof,options(tail,Options{None{},None{},None{}}))
    case _: IO.die(Unit,2,"usage: verify-bend CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-data DIR] [-q]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    argv(args)
