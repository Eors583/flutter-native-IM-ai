#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 与 Android `aiim_mnn_jni.cpp` 对齐的 MNN Transformer LLM 封装（Objective-C++ 实现见 .mm）。
@interface AiimMnnLlmEngine : NSObject

+ (instancetype)shared;

/// 静态链接 MNN 成功后为 YES。
+ (BOOL)probe;

- (BOOL)loadWithConfigPath:(NSString *)configJsonPath error:(NSError *__autoreleasing _Nullable *)error;
- (void)unloadModel;
- (void)resetSession;

- (nullable NSString *)generateWithPrompt:(NSString *)prompt
                            maxNewTokens:(NSInteger)maxNewTokens
                                   error:(NSError *__autoreleasing _Nullable *)error;

- (void)generateStreamWithPrompt:(NSString *)prompt
                    maxNewTokens:(NSInteger)maxNewTokens
                         onChunk:(void (^)(NSString *chunk))onChunk
                      onComplete:(void (^)(void))onComplete
                         onError:(void (^)(NSString *message))onError;

@end

NS_ASSUME_NONNULL_END
