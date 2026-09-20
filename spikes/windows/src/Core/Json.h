// Json.h
//
// 依存を増やさないための最小手書きJSON実装。
// spikes/darwin は Swift の Codable を使っているが、C++/WinRT標準ライブラリには
// 同等のものが無く、外部JSONライブラリ(nlohmann/json等)を導入すると
// NuGet/vcpkg依存が増えビルドの不確実性が上がるため、本スパイクの用途
// (test-assets/baseline-audio/*.json の読み込みと、RESULTS.md転記用レポートの
// 書き出し)に必要な最小限のみを実装する。
//
// 対応範囲: object / array / string / number(double) / bool / null。
// 文字列エスケープは \" \\ \/ \b \f \n \r \t \uXXXX に対応する(RFC 8259準拠、
// サロゲートペアの合成も行う)。コメント等JSON仕様外の拡張は扱わない。

#pragma once

#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace wsspike::json {

enum class Type { Null, Bool, Number, String, Array, Object };

class Value {
public:
    Value() : type_(Type::Null) {}
    static Value MakeNull() { return Value(); }
    static Value MakeBool(bool b) {
        Value v; v.type_ = Type::Bool; v.bool_ = b; return v;
    }
    static Value MakeNumber(double d) {
        Value v; v.type_ = Type::Number; v.number_ = d; return v;
    }
    static Value MakeString(std::wstring s) {
        Value v; v.type_ = Type::String; v.string_ = std::move(s); return v;
    }
    static Value MakeArray() {
        Value v; v.type_ = Type::Array; return v;
    }
    static Value MakeObject() {
        Value v; v.type_ = Type::Object; return v;
    }

    Type GetType() const { return type_; }
    bool IsNull() const { return type_ == Type::Null; }
    bool IsArray() const { return type_ == Type::Array; }
    bool IsObject() const { return type_ == Type::Object; }
    bool IsString() const { return type_ == Type::String; }

    const std::wstring& AsString() const { return string_; }
    double AsNumber() const { return number_; }
    bool AsBool() const { return bool_; }
    const std::vector<Value>& AsArray() const { return array_; }
    std::vector<Value>& AsArrayMutable() { return array_; }

    // オブジェクトのキー取得。存在しなければ Null の Value を返す(例外にしない。
    // 呼び出し側でIsNull()により必須フィールド欠落を明示的にエラーにできるようにする)。
    const Value& Get(const std::wstring& key) const;
    void Set(const std::wstring& key, Value v);
    void PushBack(Value v) { array_.push_back(std::move(v)); }

    // シリアライズ(整形出力、インデント2)。
    std::wstring Dump(int indent = 0) const;

private:
    Type type_;
    bool bool_ = false;
    double number_ = 0.0;
    std::wstring string_;
    std::vector<Value> array_;
    // 挿入順を保持するため vector<pair> で保持する(std::mapだとキー順ソートになり
    // RESULTS.md転記時の可読性が下がるため)。
    std::vector<std::pair<std::wstring, Value>> object_;

    friend Value Parse(const std::wstring&);
};

// UTF-8ファイルを読み込みパースする。失敗時は std::runtime_error を投げる。
Value ParseFile(const std::wstring& path);
Value Parse(const std::wstring& jsonText);

// UTF-8としてファイルへ書き出す。
void WriteFile(const std::wstring& path, const Value& value);

// UTF-8 <-> UTF-16 変換ヘルパー(MultiByteToWideChar/WideCharToMultiByte使用)。
std::wstring Utf8ToWide(const std::string& utf8);
std::string WideToUtf8(const std::wstring& wide);

}  // namespace wsspike::json
