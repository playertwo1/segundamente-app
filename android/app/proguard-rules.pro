-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# O código nativo dessas bibliotecas procura classes e construtores Java pelo
# nome (JNI); sem isto o R8 renomeia/remove e o app aborta ao carregar o modelo
# (ex.: NoSuchMethodError ai/onnxruntime/NodeInfo.<init> ao ligar a busca por significado).
-keep class ai.onnxruntime.** { *; }
-keep class com.k2fsa.sherpa.onnx.** { *; }
