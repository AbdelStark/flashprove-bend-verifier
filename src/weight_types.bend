import Base
import ./base_check.bend as B
import ./extension.bend as Ext

type Class is Data:
  A{}
  E{}

type Group is Data:
  Group{name: String, cls: Class, high: Bool, size: Nat, odd: Nat, bits: Nat, taken: Nat, column: Nat, left: Nat}

type WeightUnit is Data:
  WeightUnit{kind: Nat, layer: Nat, digits: Nat, columns: Nat, offset: Nat, rows: Nat, groups: List<&2,Group>}

type Layout is Data:
  Layout{width: Nat, rows: Nat, units: List<&2,WeightUnit>}

# Coordinates are in increasing bit order.
type Factor is Data:
  Equality{point: B.Elements, high_values: B.Elements}
  ArrayFactor{values: B.Elements}

type Claim is Data:
  Claim{kind: Nat, layer: Nat, factors: List<&2,Factor>, slot: Nat, shown: Ext.E3, mask_factor: Ext.E3}
