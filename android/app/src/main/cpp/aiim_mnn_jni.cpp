// JNI bridge: MNN Transformer LLM (libllm + libMNN) for Flutter.
// Config path must be absolute path to model config.json (same layout as App download).

#include <android/log.h>
#include <jni.h>
#include <sstream>
#include <streambuf>
#include <string>

#include "llm/llm.hpp"

#define LOG_TAG "AiimMnnJni"
#define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

using MNN::Transformer::Llm;

namespace {

// 返回可安全用 NewStringUTF 发出的 UTF-8 前缀长度（剩余为不完整多字节则保留到下次）
size_t Utf8CompletePrefixLen(const std::string& str) {
  size_t i = 0;
  const auto* data = reinterpret_cast<const unsigned char*>(str.data());
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

class JniChunkStreambuf : public std::streambuf {
 public:
  JniChunkStreambuf(JNIEnv* env, jobject glue, jmethodID mid_chunk)
      : env_(env), glue_(glue), mid_chunk_(mid_chunk) {}

  void FlushPending() {
    while (!pending_.empty()) {
      const size_t plen = Utf8CompletePrefixLen(pending_);
      if (plen == 0) {
        break;
      }
      std::string emit = pending_.substr(0, plen);
      pending_.erase(0, plen);
      jstring jstr = env_->NewStringUTF(emit.c_str());
      if (jstr == nullptr) {
        break;
      }
      env_->CallVoidMethod(glue_, mid_chunk_, jstr);
      env_->DeleteLocalRef(jstr);
      if (env_->ExceptionCheck()) {
        env_->ExceptionClear();
        break;
      }
    }
  }

  void DropPendingTail() { pending_.clear(); }

 protected:
  std::streamsize xsputn(const char* s, std::streamsize n) override {
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
  JNIEnv* env_;
  jobject glue_;
  jmethodID mid_chunk_;
  std::string pending_;
};

void CallOnError(JNIEnv* env, jobject glue, jmethodID mid_err, const char* msg) {
  if (glue == nullptr || mid_err == nullptr || msg == nullptr) {
    return;
  }
  jstring jmsg = env->NewStringUTF(msg);
  if (jmsg != nullptr) {
    env->CallVoidMethod(glue, mid_err, jmsg);
    env->DeleteLocalRef(jmsg);
  }
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
}

void CallOnComplete(JNIEnv* env, jobject glue, jmethodID mid_done) {
  if (glue == nullptr || mid_done == nullptr) {
    return;
  }
  env->CallVoidMethod(glue, mid_done);
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_aiim_flutter_1native_1im_1ai_mnn_MnnNativeBridge_nativeCreate(JNIEnv* env,
                                                                       jclass /* clazz */,
                                                                       jstring configPathJ) {
  if (configPathJ == nullptr) {
    return 0;
  }
  const char* p = env->GetStringUTFChars(configPathJ, nullptr);
  if (p == nullptr) {
    return 0;
  }
  std::string config_path(p);
  env->ReleaseStringUTFChars(configPathJ, p);

  Llm* llm = nullptr;
  try {
    llm = Llm::createLLM(config_path);
    if (llm == nullptr) {
      ALOGW("createLLM returned null for %s", config_path.c_str());
      return 0;
    }
    if (!llm->load()) {
      ALOGW("Llm::load failed for %s", config_path.c_str());
      Llm::destroy(llm);
      return 0;
    }
  } catch (const std::exception& e) {
    ALOGW("nativeCreate exception: %s", e.what());
    if (llm != nullptr) {
      Llm::destroy(llm);
    }
    return 0;
  } catch (...) {
    ALOGW("nativeCreate unknown exception");
    if (llm != nullptr) {
      Llm::destroy(llm);
    }
    return 0;
  }
  return reinterpret_cast<jlong>(llm);
}

JNIEXPORT void JNICALL
Java_com_aiim_flutter_1native_1im_1ai_mnn_MnnNativeBridge_nativeReset(JNIEnv* /* env */,
                                                                      jclass /* clazz */,
                                                                      jlong handle) {
  auto* llm = reinterpret_cast<Llm*>(handle);
  if (llm == nullptr) {
    return;
  }
  try {
    llm->reset();
  } catch (...) {
  }
}

JNIEXPORT jstring JNICALL
Java_com_aiim_flutter_1native_1im_1ai_mnn_MnnNativeBridge_nativeGenerate(JNIEnv* env,
                                                                         jclass /* clazz */,
                                                                         jlong handle,
                                                                         jstring userJ,
                                                                         jint maxNewTokens) {
  auto* llm = reinterpret_cast<Llm*>(handle);
  if (llm == nullptr || userJ == nullptr) {
    return env->NewStringUTF("");
  }
  const char* u = env->GetStringUTFChars(userJ, nullptr);
  if (u == nullptr) {
    return env->NewStringUTF("");
  }
  std::string user(u);
  env->ReleaseStringUTFChars(userJ, u);

  std::ostringstream oss;
  try {
    const int maxTok = maxNewTokens > 0 ? maxNewTokens : 512;
    llm->response(user, &oss, nullptr, maxTok);
  } catch (const std::exception& e) {
    ALOGW("nativeGenerate exception: %s", e.what());
    return env->NewStringUTF("");
  } catch (...) {
    ALOGW("nativeGenerate unknown exception");
    return env->NewStringUTF("");
  }
  const std::string out = oss.str();
  return env->NewStringUTF(out.c_str());
}

JNIEXPORT void JNICALL
Java_com_aiim_flutter_1native_1im_1ai_mnn_MnnNativeBridge_nativeGenerateStream(JNIEnv* env,
                                                                               jclass /* clazz */,
                                                                               jlong handle,
                                                                               jstring userJ,
                                                                               jint maxNewTokens,
                                                                               jobject glue) {
  auto* llm = reinterpret_cast<Llm*>(handle);
  if (llm == nullptr || userJ == nullptr || glue == nullptr) {
    return;
  }

  jclass glue_cls = env->GetObjectClass(glue);
  if (glue_cls == nullptr) {
    return;
  }
  jmethodID mid_chunk = env->GetMethodID(glue_cls, "onChunk", "(Ljava/lang/String;)V");
  jmethodID mid_done = env->GetMethodID(glue_cls, "onComplete", "()V");
  jmethodID mid_err = env->GetMethodID(glue_cls, "onError", "(Ljava/lang/String;)V");
  env->DeleteLocalRef(glue_cls);
  if (mid_chunk == nullptr || mid_done == nullptr || mid_err == nullptr) {
    ALOGW("nativeGenerateStream: glue method not found");
    return;
  }

  const char* u = env->GetStringUTFChars(userJ, nullptr);
  if (u == nullptr) {
    CallOnError(env, glue, mid_err, "prompt decode failed");
    CallOnComplete(env, glue, mid_done);
    return;
  }
  std::string user(u);
  env->ReleaseStringUTFChars(userJ, u);

  JniChunkStreambuf buf(env, glue, mid_chunk);
  std::ostream os(&buf);
  bool ok = true;
  try {
    const int maxTok = maxNewTokens > 0 ? maxNewTokens : 512;
    llm->response(user, &os, nullptr, maxTok);
    buf.FlushPending();
    buf.DropPendingTail();
  } catch (const std::exception& e) {
    ALOGW("nativeGenerateStream exception: %s", e.what());
    CallOnError(env, glue, mid_err, e.what());
    ok = false;
  } catch (...) {
    ALOGW("nativeGenerateStream unknown exception");
    CallOnError(env, glue, mid_err, "unknown native error");
    ok = false;
  }
  if (ok) {
    CallOnComplete(env, glue, mid_done);
  }
}

JNIEXPORT void JNICALL
Java_com_aiim_flutter_1native_1im_1ai_mnn_MnnNativeBridge_nativeRelease(JNIEnv* /* env */,
                                                                        jclass /* clazz */,
                                                                        jlong handle) {
  auto* llm = reinterpret_cast<Llm*>(handle);
  if (llm == nullptr) {
    return;
  }
  try {
    Llm::destroy(llm);
  } catch (...) {
  }
}

}  // extern "C"
