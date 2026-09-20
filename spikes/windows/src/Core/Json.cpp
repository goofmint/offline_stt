// Json.cpp
#include "pch.h"
#include "Json.h"

#include <fstream>
#include <sstream>

namespace wsspike::json {

std::wstring Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return L"";
    int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring out(len, L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), len);
    return out;
}

std::string WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return "";
    int len = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
    std::string out(len, '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), out.data(), len, nullptr, nullptr);
    return out;
}

const Value& Value::Get(const std::wstring& key) const {
    static const Value nullValue;
    for (const auto& kv : object_) {
        if (kv.first == key) return kv.second;
    }
    return nullValue;
}

void Value::Set(const std::wstring& key, Value v) {
    for (auto& kv : object_) {
        if (kv.first == key) {
            kv.second = std::move(v);
            return;
        }
    }
    object_.emplace_back(key, std::move(v));
}

namespace {

std::wstring EscapeString(const std::wstring& s) {
    std::wstring out;
    out.reserve(s.size() + 2);
    out.push_back(L'"');
    for (wchar_t c : s) {
        switch (c) {
            case L'"': out += L"\\\""; break;
            case L'\\': out += L"\\\\"; break;
            case L'\n': out += L"\\n"; break;
            case L'\r': out += L"\\r"; break;
            case L'\t': out += L"\\t"; break;
            default:
                if (c < 0x20) {
                    wchar_t buf[8];
                    swprintf_s(buf, L"\\u%04x", c);
                    out += buf;
                } else {
                    out.push_back(c);
                }
        }
    }
    out.push_back(L'"');
    return out;
}

std::wstring Indent(int n) { return std::wstring(static_cast<size_t>(n), L' '); }

}  // namespace

std::wstring Value::Dump(int indent) const {
    switch (type_) {
        case Type::Null: return L"null";
        case Type::Bool: return bool_ ? L"true" : L"false";
        case Type::Number: {
            // 整数値はできるだけ整数表記にする(RESULTS.md転記時の可読性のため)。
            if (number_ == static_cast<long long>(number_)) {
                return std::to_wstring(static_cast<long long>(number_));
            }
            std::wstringstream ss;
            ss << number_;
            return ss.str();
        }
        case Type::String: return EscapeString(string_);
        case Type::Array: {
            if (array_.empty()) return L"[]";
            std::wstring out = L"[\n";
            for (size_t i = 0; i < array_.size(); ++i) {
                out += Indent(indent + 2) + array_[i].Dump(indent + 2);
                if (i + 1 < array_.size()) out += L",";
                out += L"\n";
            }
            out += Indent(indent) + L"]";
            return out;
        }
        case Type::Object: {
            if (object_.empty()) return L"{}";
            std::wstring out = L"{\n";
            for (size_t i = 0; i < object_.size(); ++i) {
                out += Indent(indent + 2) + EscapeString(object_[i].first) + L": " + object_[i].second.Dump(indent + 2);
                if (i + 1 < object_.size()) out += L",";
                out += L"\n";
            }
            out += Indent(indent) + L"}";
            return out;
        }
    }
    return L"null";
}

namespace {

class Parser {
public:
    explicit Parser(const std::wstring& text) : text_(text), pos_(0) {}

    Value ParseValue() {
        SkipWhitespace();
        if (pos_ >= text_.size()) throw std::runtime_error("unexpected end of JSON");
        wchar_t c = text_[pos_];
        if (c == L'{') return ParseObject();
        if (c == L'[') return ParseArray();
        if (c == L'"') return Value::MakeString(ParseString());
        if (c == L't' || c == L'f') return ParseBool();
        if (c == L'n') return ParseNull();
        return ParseNumber();
    }

private:
    const std::wstring& text_;
    size_t pos_;

    void SkipWhitespace() {
        while (pos_ < text_.size() &&
               (text_[pos_] == L' ' || text_[pos_] == L'\t' || text_[pos_] == L'\n' || text_[pos_] == L'\r')) {
            ++pos_;
        }
    }

    void Expect(wchar_t c) {
        if (pos_ >= text_.size() || text_[pos_] != c) {
            throw std::runtime_error("JSON parse error: expected character");
        }
        ++pos_;
    }

    Value ParseObject() {
        Expect(L'{');
        Value obj = Value::MakeObject();
        SkipWhitespace();
        if (pos_ < text_.size() && text_[pos_] == L'}') {
            ++pos_;
            return obj;
        }
        while (true) {
            SkipWhitespace();
            std::wstring key = ParseString();
            SkipWhitespace();
            Expect(L':');
            Value v = ParseValue();
            obj.Set(key, std::move(v));
            SkipWhitespace();
            if (pos_ < text_.size() && text_[pos_] == L',') {
                ++pos_;
                continue;
            }
            Expect(L'}');
            break;
        }
        return obj;
    }

    Value ParseArray() {
        Expect(L'[');
        Value arr = Value::MakeArray();
        SkipWhitespace();
        if (pos_ < text_.size() && text_[pos_] == L']') {
            ++pos_;
            return arr;
        }
        while (true) {
            Value v = ParseValue();
            arr.PushBack(std::move(v));
            SkipWhitespace();
            if (pos_ < text_.size() && text_[pos_] == L',') {
                ++pos_;
                continue;
            }
            Expect(L']');
            break;
        }
        return arr;
    }

    std::wstring ParseString() {
        Expect(L'"');
        std::wstring out;
        while (pos_ < text_.size() && text_[pos_] != L'"') {
            wchar_t c = text_[pos_++];
            if (c == L'\\') {
                if (pos_ >= text_.size()) throw std::runtime_error("unterminated escape");
                wchar_t esc = text_[pos_++];
                switch (esc) {
                    case L'"': out.push_back(L'"'); break;
                    case L'\\': out.push_back(L'\\'); break;
                    case L'/': out.push_back(L'/'); break;
                    case L'b': out.push_back(L'\b'); break;
                    case L'f': out.push_back(L'\f'); break;
                    case L'n': out.push_back(L'\n'); break;
                    case L'r': out.push_back(L'\r'); break;
                    case L't': out.push_back(L'\t'); break;
                    case L'u': {
                        if (pos_ + 4 > text_.size()) throw std::runtime_error("bad \\u escape");
                        std::wstring hex = text_.substr(pos_, 4);
                        pos_ += 4;
                        wchar_t code = static_cast<wchar_t>(std::stoul(hex, nullptr, 16));
                        out.push_back(code);
                        break;
                    }
                    default:
                        throw std::runtime_error("unknown escape sequence");
                }
            } else {
                out.push_back(c);
            }
        }
        Expect(L'"');
        return out;
    }

    Value ParseBool() {
        if (text_.compare(pos_, 4, L"true") == 0) {
            pos_ += 4;
            return Value::MakeBool(true);
        }
        if (text_.compare(pos_, 5, L"false") == 0) {
            pos_ += 5;
            return Value::MakeBool(false);
        }
        throw std::runtime_error("invalid literal");
    }

    Value ParseNull() {
        if (text_.compare(pos_, 4, L"null") == 0) {
            pos_ += 4;
            return Value::MakeNull();
        }
        throw std::runtime_error("invalid literal");
    }

    Value ParseNumber() {
        size_t start = pos_;
        if (pos_ < text_.size() && (text_[pos_] == L'-' || text_[pos_] == L'+')) ++pos_;
        while (pos_ < text_.size() &&
               (iswdigit(text_[pos_]) || text_[pos_] == L'.' || text_[pos_] == L'e' || text_[pos_] == L'E' ||
                text_[pos_] == L'-' || text_[pos_] == L'+')) {
            ++pos_;
        }
        std::wstring numText = text_.substr(start, pos_ - start);
        return Value::MakeNumber(std::stod(numText));
    }
};

}  // namespace

Value Parse(const std::wstring& jsonText) {
    Parser parser(jsonText);
    return parser.ParseValue();
}

Value ParseFile(const std::wstring& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        throw std::runtime_error("cannot open JSON file: " + WideToUtf8(path));
    }
    std::stringstream ss;
    ss << file.rdbuf();
    std::string utf8 = ss.str();
    // UTF-8 BOM除去
    if (utf8.size() >= 3 && static_cast<unsigned char>(utf8[0]) == 0xEF &&
        static_cast<unsigned char>(utf8[1]) == 0xBB && static_cast<unsigned char>(utf8[2]) == 0xBF) {
        utf8 = utf8.substr(3);
    }
    return Parse(Utf8ToWide(utf8));
}

void WriteFile(const std::wstring& path, const Value& value) {
    std::ofstream file(path, std::ios::binary);
    if (!file) {
        throw std::runtime_error("cannot open JSON file for write: " + WideToUtf8(path));
    }
    std::string utf8 = WideToUtf8(value.Dump(0));
    file.write(utf8.data(), static_cast<std::streamsize>(utf8.size()));
}

}  // namespace wsspike::json
