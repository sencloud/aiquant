import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum TxnType { buy, sell, dividend }

class PortfolioTransaction extends HiveObject {
  String id;
  String portfolioId;
  String symbol;
  String name;
  String sector;
  String assetClass;
  String type; // buy / sell / dividend
  double quantity;
  double price;
  double totalValue;
  DateTime date;
  String notes;

  PortfolioTransaction({
    String? id,
    required this.portfolioId,
    required this.symbol,
    this.name = '',
    this.sector = '',
    this.assetClass = '',
    required this.type,
    required this.quantity,
    required this.price,
    double? totalValue,
    DateTime? date,
    this.notes = '',
  })  : id = id ?? _uuid.v4(),
        totalValue = totalValue ?? quantity * price,
        date = date ?? DateTime.now();
}

class PortfolioTransactionAdapter extends TypeAdapter<PortfolioTransaction> {
  @override
  final int typeId = 2;

  @override
  PortfolioTransaction read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return PortfolioTransaction(
      id: fields[0] as String,
      portfolioId: fields[1] as String,
      symbol: fields[2] as String,
      name: fields[3] as String? ?? '',
      sector: fields[4] as String? ?? '',
      assetClass: fields[5] as String? ?? '',
      type: fields[6] as String,
      quantity: (fields[7] as num).toDouble(),
      price: (fields[8] as num).toDouble(),
      totalValue: (fields[9] as num).toDouble(),
      date: fields[10] as DateTime,
      notes: fields[11] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, PortfolioTransaction obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.portfolioId)
      ..writeByte(2)
      ..write(obj.symbol)
      ..writeByte(3)
      ..write(obj.name)
      ..writeByte(4)
      ..write(obj.sector)
      ..writeByte(5)
      ..write(obj.assetClass)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.quantity)
      ..writeByte(8)
      ..write(obj.price)
      ..writeByte(9)
      ..write(obj.totalValue)
      ..writeByte(10)
      ..write(obj.date)
      ..writeByte(11)
      ..write(obj.notes);
  }
}
