#import "AiimMnnLlmEngine.h"

#include <sstream>
#include <streambuf>
#include <string>

#include "llm/llm.hpp"

using MNN::Transformer::Llm;

namespace {

// 与 android/app/src/main/cpp/aiim_mnn_jni.cpp 一致：只下发完整 UTF-8 前缀，避免半个汉字。
size_t Utf8CompletePrefixLen(const std::string &str) {
  size_t i = 0;
  const auto *data = reinterpret_cast<const unsigned char *>(str.data());
  const size_t n = str.size();
  while (i < n) {
    const unsigned char c = data[i];
    size_t len = 1;
    if ((c & 0x80) == 0) {
      len = 1;
    } else if ((c & 0xE0) == 0xC0) {
      len = 2;
    } else if ((c & 0xF0) == 0xE0) {
      len = 3;
    } else if ((c & 0xF8) == 0xF0) {
      len = 4;
    } else {
      break;
    }
    if (i + len > n) {
      break;
    }
    for (size_t k = 1; k < len; ++k) {
      if ((data[i + k] & 0xC0) != 0x80) {
        len = 0;
        break;
      }
    }
    if (len == 0) {
      break;
    }
    i += len;
  }
  return i;
}

class Utf8ChunkStreambuf : public std::streambuf {
 public:
  explicit Utf8ChunkStreambuf(void (^onChunk)(NSString *)) : onChunk_(onChunk) {}

  void FlushPending() {
    while (!pending_.empty()) {
      const size_t plen = Utf8CompletePrefixLen(pending_);
      if (plen == 0) {
        break;
      }
      std::string emit = pending_.substr(0, plen);
      pending_.erase(0, plen);
      NSString *ns = [[NSString alloc] initWithBytes:emit.data()
                                                length:emit.length()
                                              encoding:NSUTF8StringEncoding];
      if (ns.length > 0 && onChunk_) {
        onChunk_(ns);
      }
    }
  }

  void DropPendingTail() { pending_.clear(); }

 protected:
  std::streamsize xsputn(const char *s, std::streamsize n) override {
    if (n <= 0) {
      return 0;
    }
    pending_.append(s, static_cast<size_t>(n));
    FlushPending();
    return n;
  }

  int_type overflow(int_type c) override {
    if (c == traits_type::eof()) {
      return traits_type::not_eof(c);
    }
    char ch = traits_type::to_char_type(c);
    pending_.push_back(ch);
    FlushPending();
    return c;
  }

 private:
  void (^onChunk_)(NSString *);
  std::string pending_;
};

static NSError *AiimMakeError(NSString *msg) {
  return [NSError errorWithDomain:@"AiimMnn"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : msg ?: @""}];
}

}  // namespace

@implementation AiimMnnLlmEngine {
  Llm *_llm;
}

+ (instancetype)shared {
  static AiimMnnLlmEngine *inst;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    inst = [[AiimMnnLlmEngine alloc] init];
  });
  return inst;
}

+ (BOOL)probe {
  return YES;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _llm = nullptr;
  }
  return self;
}

- (void)dealloc {
  [self unloadModel];
}

- (void)unloadModel {
  if (_llm != nullptr) {
    try {
      Llm::destroy(_llm);
    } catch (...) {
    }
    _llm = nullptr;
  }
}

- (BOOL)loadWithConfigPath:(NSString *)configJsonPath error:(NSError *__autoreleasing _Nullable *)error {
  if (configJsonPath.length == 0) {
    if (error) {
      *error = AiimMakeError(@"config path empty");
    }
    return NO;
  }
  [self unloadModel];

  std::string path = std::string([configJsonPath UTF8String]);
  Llm *llm = nullptr;
  try {
    llm = Llm::createLLM(path);
    if (llm == nullptr) {
      if (error) {
        *error = AiimMakeError(@"Llm::createLLM returned null");
      }
      return NO;
    }
    NSString *tmp = NSTemporaryDirectory();
    std::string tmpUtf8 = tmp ? std::string([tmp UTF8String]) : "";
    std::string cfg =
        std::string("{\"tmp_path\":\"") + tmpUtf8 + "\",\"use_mmap\":true}";
    llm->set_config(cfg);
    if (!llm->load()) {
      Llm::destroy(llm);
      if (error) {
        *error = AiimMakeError(@"Llm::load failed");
      }
      return NO;
    }
  } catch (const std::exception &e) {
    if (llm != nullptr) {
      Llm::destroy(llm);
    }
    if (error) {
      *error = AiimMakeError([NSString stringWithUTF8String:e.what()]);
    }
    return NO;
  } catch (...) {
    if (llm != nullptr) {
      Llm::destroy(llm);
    }
    if (error) {
      *error = AiimMakeError(@"native load failed");
    }
    return NO;
  }

  _llm = llm;
  return YES;
}

- (void)resetSession {
  if (_llm == nullptr) {
    return;
  }
  try {
    _llm->reset();
  } catch (...) {
  }
}

- (nullable NSString *)generateWithPrompt:(NSString *)prompt
                            maxNewTokens:(NSInteger)maxNewTokens
                                   error:(NSError *__autoreleasing _Nullable *)error {
  if (_llm == nullptr) {
    if (error) {
      *error = AiimMakeError(@"Model not loaded");
    }
    return nil;
  }
  if (prompt == nil) {
    if (error) {
      *error = AiimMakeError(@"prompt required");
    }
    return nil;
  }
  std::ostringstream oss;
  try {
    const int maxTok = maxNewTokens > 0 ? (int)maxNewTokens : 512;
    _llm->response(std::string([prompt UTF8String]), &oss, nullptr, maxTok);
  } catch (const std::exception &e) {
    if (error) {
      *error = AiimMakeError([NSString stringWithUTF8String:e.what()]);
    }
    return nil;
  } catch (...) {
    if (error) {
      *error = AiimMakeError(@"generate failed");
    }
    return nil;
  }
  const std::string out = oss.str();
  return [[NSString alloc] initWithBytes:out.data()
                                    length:out.size()
                                  encoding:NSUTF8StringEncoding];
}

- (void)generateStreamWithPrompt:(NSString *)prompt
                    maxNewTokens:(NSInteger)maxNewTokens
                         onChunk:(void (^)(NSString *chunk))onChunk
                      onComplete:(void (^)(void))onComplete
                         onError:(void (^)(NSString *message))onError {
  if (_llm == nullptr) {
    if (onError) {
      onError(@"Model not loaded");
    }
    if (onComplete) {
      onComplete();
    }
    return;
  }
  if (prompt == nil) {
    if (onError) {
      onError(@"prompt required");
    }
    if (onComplete) {
      onComplete();
    }
    return;
  }

  Utf8ChunkStreambuf buf(onChunk);
  std::ostream os(&buf);
  bool ok = YES;
  try {
    const int maxTok = maxNewTokens > 0 ? (int)maxNewTokens : 512;
    _llm->response(std::string([prompt UTF8String]), &os, nullptr, maxTok);
    buf.FlushPending();
    buf.DropPendingTail();
  } catch (const std::exception &e) {
    ok = NO;
    if (onError) {
      onError([NSString stringWithUTF8String:e.what()]);
    }
  } catch (...) {
    ok = NO;
    if (onError) {
      onError(@"stream generate failed");
    }
  }
  if (ok && onComplete) {
    onComplete();
  }
}

@end
