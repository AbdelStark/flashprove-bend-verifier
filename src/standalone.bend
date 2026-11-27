import Base
import ./policy_statement.bend as S
import ./policy_config.bend as Config
import ./commitment.bend as Commitment
import ./header.bend as Header
import ./key_stage.bend as Key
import ./leaf_stage.bend as Leaf
import ./leaf_check.bend as Link
import ./request_stage.bend as Req
import ./result.bend as Result
import ./hash_bytes.bend as H
import ./opening_bytes.bend as O

def usage() -> String:
  "usage: verify-bend CONFIG IVK REQUEST Y PROOF -id HEX [-policy POLICY] [-data DIR] [-q] [-j WORKERS] [-timing]"

type Options is Data:
  Options{id: Maybe<&2,String>, policy: Maybe<&2,String>, public: Maybe<&2,String>, timing: Bool}

def options(args: List<String>, opt: Options) -> Maybe<&2,Options>:
  match args opt:
    case Nil{} final: Some{final}
    case "-id" <> id <> tail Options{None{},p,d,t}: options(tail,Options{Some{id},p,d,t})
    case "-policy" <> policy <> tail Options{i,None{},d,t}: options(tail,Options{i,Some{policy},d,t})
    case "-data" <> folder <> tail Options{i,p,None{},t}: options(tail,Options{i,p,Some{folder},t})
    case "-timing" <> tail Options{i,p,d,False{}}: options(tail,Options{i,p,d,True{}})
    case "-j" <> "1" <> tail state: options(tail,state)
    case "-q" <> tail state: options(tail,state)
    case _ _: None{}

# REQ-PERF-2. With -timing, one line per stage on the error stream; standard output never changes.
def report(on: Bool, text: String) -> IO(Unit):
  match on:
    case True{}: IO.print_err(text)
    case False{}: IO.pure(Unit,Unit{})

# REQ-ASSURE-4. Each stage names itself and the caller's file on stderr before it starts,
# so a refusal's `NO:` line follows the stage and file that refused.
def enter(place: String) -> IO(Unit):
  IO.print_err("stage: " ++ place)

# Prints the milliseconds since `since` under `stage` and answers the current time.
def lap(on: Bool, stage: String, since: Nat) -> IO(Nat):
  do IO<Nat>:
    +now : Nat <- IO.now()
    shown : Unit <- report(on,"timing: " ++ stage ++ " " ++ Nat.show(Nat.sub(now,since)) ++ " ms")
    return now

type Call is Data:
  Call{ivk: String, proof: String, expected: String, plans: String, build: String, cfg: Config.Configured, statement: S.Statement,
    timing: Bool, start: Nat, mark: Nat}

def digest(cfg: Config.Configured) -> H.Bytes:
  Config.Configured{value,_} = cfg
  value

def request(checked: Link.Checked, +call: Call, +copy: U32, +mark: Nat) -> IO(Unit):
  Link.Checked{leaf,session,_} = checked
  Call{_,proof,id,plans,build,+cfg,+st,+timing,start,_} = call
  do IO<Unit>:
    begun : Unit <- enter("request, file: PROOF")
    evidence : Req.Trace <- Req.verify(proof,copy,st,cfg,plans,leaf,session)
    +done : Nat <- lap(timing,"request",mark)
    whole : Unit <- report(timing,"timing: total " ++ Nat.show(Nat.sub(done,start)) ++ " ms")
    Result.print(st,digest(cfg),String.to_lower(id),copy,build)

def entry(key: Key.AttestedKey, +call: Call) -> IO(Unit):
  Key.AttestedKey{+root,+record,_,_,_,session} = key
  Call{ivk,proof,expected,plans,_,+cfg,st,timing,_,mark} = call
  +hash = digest(cfg)
  do IO<Unit>:
    id : String <- Commitment.from_record(Config.key_shape(st),O.digest_bytes(root),record,hash)
    named : Unit <- Header.require(String.eq(id,String.to_lower(expected)),"NO: model-statement")
    proof_head : Unit <- enter("leaf, file: PROOF")
    head : H.Bytes <- Header.bytes(proof,12)
    +copy : U32 <- Header.leaf_index(head)
    begun : Unit <- enter("leaf, file: IVK/leaf/" ++ U32.show(copy) ++ ".bin")
    trace : Leaf.Trace <- Leaf.inspect(ivk ++ "/leaf/" ++ U32.show(copy) ++ ".bin",hash,plans,Leaf.Table{root,record},session)
    link : Link.Checked <- Link.algebra(trace,hash)
    linked : Nat <- lap(timing,"leaf",mark)
    request(link,call,copy,linked)

def run(+config: String, +ivk: String, req: String, y: String, proof: String, build: String, opt: Maybe<&2,Options>) -> IO(Unit):
  match opt:
    case Some{Options{Some{id},policy,dir,+timing}}:
      +public = Maybe.default(&2,String,dir,"build")
      +plans = public ++ "/plans"
      do IO<Unit>:
        workers : U32 <- IO.thread_count()
        counted : Unit <- report(timing,"timing: workers " ++ U32.show(workers))
        +start : Nat <- IO.now()
        begun : Unit <- enter("public, files: CONFIG, REQUEST, Y, DIR")
        +st : S.Statement <- S.load(config,req,y,public ++ "/tables",policy)
        +cfg : Config.Configured <- Config.load(st,config,plans)
        loaded : Nat <- lap(timing,"public",start)
        keying : Unit <- enter("key, file: IVK/key.bin")
        key : Key.AttestedKey <- Key.check_transcript(ivk ++ "/key.bin",digest(cfg),plans)
        keyed : Nat <- lap(timing,"key",loaded)
        entry(key,Call{ivk,proof,id,plans,build,cfg,st,timing,start,keyed})
    case _: IO.die(Unit,2,usage())

def argv(args: List<String>,build: String) -> IO(Unit):
  match args:
    case _ <> config <> ivk <> req <> y <> proof <> tail:
      run(config,ivk,req,y,proof,build,options(tail,Options{None{},None{},None{},False{}}))
    case _: IO.die(Unit,2,usage())

def run_build(build: String) -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    argv(args,build)
