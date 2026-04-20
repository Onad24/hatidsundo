import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

/// User roles in the application
enum UserRole {
  @JsonValue('client')
  client,
  @JsonValue('rider')
  rider,
  @JsonValue('admin')
  admin,
  @JsonValue('none')
  none,
}

/// User model representing all user types
@JsonSerializable()
class UserModel {
  final String id;
  final String name;
  final UserRole role;
  final String? phone;
  final String email;
  final String? avatarUrl;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.role,
    this.phone,
    required this.email,
    this.avatarUrl,
    required this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserModelToJson(this);

  UserModel copyWith({
    String? id,
    String? name,
    UserRole? role,
    String? phone,
    String? email,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isClient => role == UserRole.client;
  bool get isRider => role == UserRole.rider;
  bool get isAdmin => role == UserRole.admin;
}
