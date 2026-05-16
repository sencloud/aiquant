import 'dart:convert';

/// 工具的 OpenAI 兼容 JSON Schema 入参描述。
///
/// `properties` 是一组字段名 → 字段定义；字段定义形如：
/// ```dart
/// {'type': 'string', 'description': '股票 ts_code，例如 600519.SH'}
/// ```
class ToolParameterSchema {
  const ToolParameterSchema({
    required this.properties,
    this.required = const [],
  });

  final Map<String, Map<String, dynamic>> properties;
  final List<String> required;

  Map<String, dynamic> toJsonSchema() => {
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
      };
}

/// 一个可被 AI 调用的工具。
abstract class AiTool {
  /// OpenAI/DeepSeek 协议里 function.name；只能字母+数字+下划线。
  String get name;

  /// AI 看的中文/英文描述（决定它什么时候调用这个工具）
  String get description;

  /// 入参 schema
  ToolParameterSchema get parameters;

  /// 执行逻辑。返回字符串将作为 role=tool 消息内容喂回模型。
  /// **不应该自己捕获并吞掉异常**——抛出错误会被 registry 包装为
  /// `{"error": "..."}` JSON，喂回模型让它自行处理。
  Future<String> run(Map<String, dynamic> args);

  /// 序列化成 OpenAI tools[] 数组里的一项
  Map<String, dynamic> toOpenAiJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters.toJsonSchema(),
        },
      };
}

/// 工具注册表 — 集中管理 + 根据名字派发执行。
class ToolRegistry {
  ToolRegistry(List<AiTool> tools)
      : _tools = {for (final t in tools) t.name: t};

  final Map<String, AiTool> _tools;

  List<AiTool> get all => _tools.values.toList(growable: false);
  bool get isEmpty => _tools.isEmpty;

  /// 转成 OpenAI/DeepSeek 协议要求的 tools 数组
  List<Map<String, dynamic>> toOpenAiList() =>
      [for (final t in _tools.values) t.toOpenAiJson()];

  /// 派发执行：找到对应工具 → 反序列化参数 → 调用 → 返回 JSON 字符串。
  /// 任何错误（找不到工具、参数 JSON 错误、工具内部异常）都会被包装成
  /// `{"error": "..."}` 字符串返回，喂回 LLM 让它处理。
  Future<String> dispatch(String name, String argumentsJson) async {
    final tool = _tools[name];
    if (tool == null) {
      return jsonEncode({'error': '未知工具：$name'});
    }
    Map<String, dynamic> args;
    try {
      final decoded = argumentsJson.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(argumentsJson) as Map<String, dynamic>;
      args = decoded;
    } catch (e) {
      return jsonEncode({'error': '参数 JSON 解析失败：$e', 'raw': argumentsJson});
    }
    try {
      final result = await tool.run(args);
      return result;
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }
}
