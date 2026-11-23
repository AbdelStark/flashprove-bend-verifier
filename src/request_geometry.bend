# Generated from configuration-only H821 plans by scripts/request-geometry.py.
import Base
import ./plan_types.bend as P
import ./key_stage_geometry.bend as G

def small(chain: P.Chain) -> G.Schedule:
  match chain:
    case P.RequestFirst{}:
      [[G.Tree{G.Local{0n},18n,71n,40n},G.Tree{G.Local{2n},18n,6n,40n},G.Tree{G.Local{3n},18n,129n,40n}],
       [G.Tree{G.Local{4n},18n,39n,40n},G.Tree{G.Local{5n},18n,3n,40n},G.Tree{G.Local{6n},18n,61n,40n}],
       [G.Tree{G.Local{7n},18n,77n,40n},G.Tree{G.Local{8n},18n,6n,40n},G.Tree{G.Local{9n},18n,129n,40n}],
       [G.Tree{G.Local{10n},18n,39n,40n},G.Tree{G.Local{11n},18n,3n,40n},G.Tree{G.Local{12n},18n,61n,40n}],
       [G.Tree{G.Local{13n},18n,47n,40n},G.Tree{G.Local{14n},18n,3n,40n},G.Tree{G.Local{15n},18n,81n,40n}],
       [G.Tree{G.Local{16n},18n,9n,40n}],
       [G.Tree{G.Local{17n},17n,96n,40n}],
       [G.Tree{G.Local{18n},16n,72n,40n}],
       [G.Tree{G.Local{19n},15n,72n,40n}],
       [G.Tree{G.Local{20n},15n,12n,40n}]]
    case P.RequestShared{}:
      [[G.Tree{G.Table{},23n,256n,40n}],
       [G.Tree{G.Local{0n},17n,57n,40n},G.Tree{G.Local{2n},13n,3n,40n}],
       [G.Tree{G.Local{3n},14n,72n,40n}],
       [G.Tree{G.Local{4n},14n,12n,40n}],
       [G.Tree{G.Local{1n},18n,12n,40n},G.Tree{G.Local{2n},13n,3n,40n},G.Tree{G.Local{5n},13n,3n,40n}],
       [G.Tree{G.Local{6n},14n,96n,40n}],
       [G.Tree{G.Local{7n},15n,12n,40n}]]
    case P.RequestSecond{}:
      [[G.Tree{G.Local{1n},13n,3n,40n},G.Tree{G.Local{21n},18n,6n,40n},G.Tree{G.Local{22n},18n,12n,40n}],
       [G.Tree{G.Local{23n},14n,96n,40n}],
       [G.Tree{G.Local{24n},15n,12n,40n}]]
    case _: []

def full(chain: P.Chain) -> G.Schedule:
  match chain:
    case P.RequestFirst{}:
      [[G.Tree{G.Local{0n},23n,124n,40n},G.Tree{G.Local{2n},23n,3n,40n},G.Tree{G.Local{3n},23n,31n,40n}],
       [G.Tree{G.Local{4n},23n,66n,40n},G.Tree{G.Local{5n},23n,3n,40n},G.Tree{G.Local{6n},23n,14n,40n}],
       [G.Tree{G.Local{7n},23n,131n,40n},G.Tree{G.Local{8n},23n,3n,40n},G.Tree{G.Local{9n},23n,31n,40n}],
       [G.Tree{G.Local{10n},23n,66n,40n},G.Tree{G.Local{11n},23n,3n,40n},G.Tree{G.Local{12n},23n,14n,40n}],
       [G.Tree{G.Local{13n},23n,131n,40n},G.Tree{G.Local{14n},23n,3n,40n},G.Tree{G.Local{15n},23n,31n,40n}],
       [G.Tree{G.Local{16n},23n,66n,40n},G.Tree{G.Local{17n},23n,3n,40n},G.Tree{G.Local{18n},23n,14n,40n}],
       [G.Tree{G.Local{19n},23n,131n,40n},G.Tree{G.Local{20n},23n,3n,40n},G.Tree{G.Local{21n},23n,31n,40n}],
       [G.Tree{G.Local{22n},23n,66n,40n},G.Tree{G.Local{23n},23n,3n,40n},G.Tree{G.Local{24n},23n,14n,40n}],
       [G.Tree{G.Local{25n},23n,131n,40n},G.Tree{G.Local{26n},23n,3n,40n},G.Tree{G.Local{27n},23n,31n,40n}],
       [G.Tree{G.Local{28n},23n,66n,40n},G.Tree{G.Local{29n},23n,3n,40n},G.Tree{G.Local{30n},23n,14n,40n}],
       [G.Tree{G.Local{31n},23n,131n,40n},G.Tree{G.Local{32n},23n,3n,40n},G.Tree{G.Local{33n},23n,31n,40n}],
       [G.Tree{G.Local{34n},23n,66n,40n},G.Tree{G.Local{35n},23n,3n,40n},G.Tree{G.Local{36n},23n,14n,40n}],
       [G.Tree{G.Local{37n},23n,131n,40n},G.Tree{G.Local{38n},23n,3n,40n},G.Tree{G.Local{39n},23n,31n,40n}],
       [G.Tree{G.Local{40n},23n,66n,40n},G.Tree{G.Local{41n},23n,3n,40n},G.Tree{G.Local{42n},23n,14n,40n}],
       [G.Tree{G.Local{43n},23n,131n,40n},G.Tree{G.Local{44n},23n,3n,40n},G.Tree{G.Local{45n},23n,31n,40n}],
       [G.Tree{G.Local{46n},23n,66n,40n},G.Tree{G.Local{47n},23n,3n,40n},G.Tree{G.Local{48n},23n,14n,40n}],
       [G.Tree{G.Local{49n},23n,131n,40n},G.Tree{G.Local{50n},23n,3n,40n},G.Tree{G.Local{51n},23n,31n,40n}],
       [G.Tree{G.Local{52n},23n,66n,40n},G.Tree{G.Local{53n},23n,3n,40n},G.Tree{G.Local{54n},23n,14n,40n}],
       [G.Tree{G.Local{55n},23n,131n,40n},G.Tree{G.Local{56n},23n,3n,40n},G.Tree{G.Local{57n},23n,31n,40n}],
       [G.Tree{G.Local{58n},23n,66n,40n},G.Tree{G.Local{59n},23n,3n,40n},G.Tree{G.Local{60n},23n,14n,40n}],
       [G.Tree{G.Local{61n},23n,131n,40n},G.Tree{G.Local{62n},23n,3n,40n},G.Tree{G.Local{63n},23n,31n,40n}],
       [G.Tree{G.Local{64n},23n,66n,40n},G.Tree{G.Local{65n},23n,3n,40n},G.Tree{G.Local{66n},23n,14n,40n}],
       [G.Tree{G.Local{67n},23n,131n,40n},G.Tree{G.Local{68n},23n,3n,40n},G.Tree{G.Local{69n},23n,31n,40n}],
       [G.Tree{G.Local{70n},23n,66n,40n},G.Tree{G.Local{71n},23n,3n,40n},G.Tree{G.Local{72n},23n,14n,40n}],
       [G.Tree{G.Local{73n},23n,118n,40n},G.Tree{G.Local{74n},23n,3n,40n},G.Tree{G.Local{75n},23n,24n,40n}],
       [G.Tree{G.Local{76n},23n,9n,40n}],
       [G.Tree{G.Local{77n},22n,96n,40n}],
       [G.Tree{G.Local{78n},19n,72n,40n}],
       [G.Tree{G.Local{79n},16n,72n,40n}],
       [G.Tree{G.Local{80n},13n,144n,40n}],
       [G.Tree{G.Local{81n},15n,12n,40n}]]
    case P.RequestShared{}:
      [[G.Tree{G.Table{},32n,2048n,40n}],
       [G.Tree{G.Local{0n},24n,324n,40n},G.Tree{G.Local{2n},13n,3n,40n}],
       [G.Tree{G.Local{3n},21n,120n,40n}],
       [G.Tree{G.Local{4n},17n,72n,40n}],
       [G.Tree{G.Local{5n},13n,72n,40n}],
       [G.Tree{G.Local{6n},14n,12n,40n}],
       [G.Tree{G.Local{1n},22n,36n,40n},G.Tree{G.Local{2n},13n,3n,40n},G.Tree{G.Local{7n},13n,3n,40n}],
       [G.Tree{G.Local{8n},18n,96n,40n}],
       [G.Tree{G.Local{9n},14n,96n,40n}],
       [G.Tree{G.Local{10n},15n,12n,40n}]]
    case P.RequestSecond{}:
      [[G.Tree{G.Local{1n},13n,3n,40n},G.Tree{G.Local{82n},22n,12n,40n},G.Tree{G.Local{83n},22n,36n,40n}],
       [G.Tree{G.Local{84n},18n,96n,40n}],
       [G.Tree{G.Local{85n},15n,72n,40n}],
       [G.Tree{G.Local{86n},13n,72n,40n}],
       [G.Tree{G.Local{87n},15n,12n,40n}]]
    case _: []

def schedule(profile: P.Profile, chain: P.Chain) -> G.Schedule:
  match profile:
    case P.SmallExact{}: small(chain)
    case P.SmallClipped{}: small(chain)
    case P.FullExact{}: full(chain)
    case P.FullClipped{}: full(chain)
