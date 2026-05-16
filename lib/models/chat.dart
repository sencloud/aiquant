import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class ChatMessage extends HiveObject {
  String id;
  String role; // user / assistant / system
  String content;
  String? reasoning; // optional reasoning trace ("深度模式")
  DateTime timestamp;
  bool streaming;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.reasoning,
    DateTime? timestamp,
    this.streaming = false,
  })  : id = id ?? _uuid.v4(),
        timestamp = timestamp ?? DateTime.now();
}

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 3;

  @override
  ChatMessage read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      role: fields[1] as String,
      content: fields[2] as String,
      reasoning: fields[3] as String?,
      timestamp: fields[4] as DateTime,
      streaming: fields[5] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.role)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.reasoning)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.streaming);
  }
}

class ChatSession extends HiveObject {
  String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;
  String model;
  bool deepMode;
  List<ChatMessage> messages;

  ChatSession({
    String? id,
    this.title = '新对话',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.model = 'deepseek-reasoner',
    this.deepMode = true,
    List<ChatMessage>? messages,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? <ChatMessage>[];
}

class ChatSessionAdapter extends TypeAdapter<ChatSession> {
  @override
  final int typeId = 4;

  @override
  ChatSession read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return ChatSession(
      id: fields[0] as String,
      title: fields[1] as String,
      createdAt: fields[2] as DateTime,
      updatedAt: fields[3] as DateTime,
      model: fields[4] as String,
      deepMode: fields[5] as bool,
      messages: (fields[6] as List).cast<ChatMessage>(),
    );
  }

  @override
  void write(BinaryWriter writer, ChatSession obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.model)
      ..writeByte(5)
      ..write(obj.deepMode)
      ..writeByte(6)
      ..write(obj.messages);
  }
}
