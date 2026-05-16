/// Per-instrument lot returned by [AssetQuantityDialog]. Kept in its own file
/// so both the picker dialog and the quantity dialog can reference the same
/// concrete type without a circular import.
class AssetLot {
  final double qty;
  final double price;
  const AssetLot(this.qty, this.price);
}
