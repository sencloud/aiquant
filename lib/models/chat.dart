import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// AI 工具调用请求（assistant 消息携带）。
class ToolCall {
  String id;
  String name;
  /// 序列化后的 JSON 字符串参数（OpenAI 协议规定 string 而非 object）
  String argumentsJson;

  ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  Map<String, dynamic> toOpenAiJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': argumentsJson,
        },
      };
}

class ToolCallAdapter extends TypeAdapter<ToolCall> {
  @override
  final int typeId = 5;

  @override
  ToolCall read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return ToolCall(
      id: fields[0] as String,
      name: fields[1] as String,
      argumentsJson: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ToolCall obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.argumentsJson);
  }
}

/// 一条对话消息。
///
/// role:
///   - user / assistant / system：常规
///   - tool：工具执行结果（必须填 toolCallId、name）
///
/// toolCalls：assistant 消息发起的工具调用（可能不止一个）
class ChatMessage extends HiveObject {
  String id;
  String role;
  String content;
  String? reasoning;
  DateTime timestamp;
  bool streaming;

  /// assistant 消息：本轮请求触发的工具调用列表
  List<ToolCall>? toolCalls;

  /// role=tool 消息：对应 assistant 触发的 tool_call_id
  String? toolCallId;

  /// role=tool 消息：对应工具名称
  String? name;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.reasoning,
    DateTime? timestamp,
    this.streaming = false,
    this.toolCalls,
    this.toolCallId,
    this.name,
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
      toolCalls: (fields[6] as List?)?.cast<ToolCall>(),
      toolCallId: fields[7] as String?,
      name: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(9)
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
      ..write(obj.streaming)
      ..writeByte(6)
      ..write(obj.toolCalls)
      ..writeByte(7)
      ..write(obj.toolCallId)
      ..writeByte(8)
      ..write(obj.name);
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

  /// Persona id（绑定 lib/models/persona.dart 内置库）
  String personaId;

  /// 是否启用工具调用（具体模型由服务端决定）
  bool toolsEnabled;

  ChatSession({
    String? id,
    this.title = '新对话',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.model = '',
    this.deepMode = false,
    List<ChatMessage>? messages,
    this.personaId = 'default',
    this.toolsEnabled = true,
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
      personaId: fields[7] as String? ?? 'default',
      toolsEnabled: fields[8] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, ChatSession obj) {
    writer
      ..writeByte(9)
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
      ..write(obj.messages)
      ..writeByte(7)
      ..write(obj.personaId)
      ..writeByte(8)
      ..write(obj.toolsEnabled);
  }
}
