# El runtime empaquetado, sus callbacks y sus bindings se resuelven desde código nativo.
-keep class com.yausername.** { *; }
-dontwarn com.yausername.**
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**
-keepattributes Signature,InnerClasses,EnclosingMethod
-keepclasseswithmembernames class * { native <methods>; }
