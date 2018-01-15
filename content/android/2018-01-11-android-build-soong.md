---
title: "Android编译系统-Android.bp"
date: 2018-01-11 15:30
---

[Soong](https://android.googlesource.com/platform/build/soong/)是替换android中基于make的构建系统，用Android.bp文件替换Android.mk文件，并使用类似于JSON的格式来描述一个模块的构建。

## Android.bp文件格式

Android.bp文件设计的非常简单，没有条件判断或者控制流语句，在Go中编写的构建逻辑中处理任何复杂情况。Android.bp文件的语法和语义可能与Bazel BUILD文件类似。

## 模块

Android.bp 文件中的模块以一个模块类型开始，后面跟着一组属性，以名值对(`name: value`)表示。格式为：

```go
cc_binary {
    name: "gzip",
    srcs: ["src/test/minigzip.c"],
    shared_libs: ["libz"],
    stl: "none",
}
```

每个模块必须有一个`name`属性，并且在所有的Android.bp文件中必须是唯一的。

有效模块类型及其属性的列表，请参阅 `$OUT_DIR/soong/.bootstrap/docs/soong_build.html`

## 变量

Android.bp文件可能包含顶级变量并赋值。

```go
gzip_srcs = ["src/test/minigzip.c"],

cc_binary {
    name: "gzip",
    srcs: gzip_srcs,
    shared_libs: ["libz"],
    stl: "none",
}
```

变量的范围被限定为它们声明的文件的剩余部分，以及任何子 blueprint 文件。一个例外是变量不可变，能够被 += 进行附加赋值，而且只能在被引用之前。

## 注释

Android.bp文件能包含C风格的多行`/* */`注释和C++风格的单行注释`//`。

## 类型

变量和属性是强类型的，基于第一个赋值动态变量，以及模块类型静态属性。他们支持的类型有：

- 布尔型（`true`or`false`)
- 整型（`int`）
- 字符串（`string`）
- 字符串列表（`"string1"`, `"string2"`）
- Maps (`{key1: "value1", key2: ["value2"]}`)

Map 可以包含任意类型的值，包括嵌套的maps。列表和 maps 允许在最后一个值之后有逗号。

## 操作符

字符串、字符串列表、和maps能使用`+`操作符进行附加。整型可以用`+`操作符来总结。 附加的maps将生成两个map中键的并集，并附加的两个map中存在任何键的值。

## 缺省模块

缺省模块可用于在多个模块中重复相同的属性，例如：

```go
cc_defaults {
    name: "gzip_defaults",
    shared_libs: ["libz"],
    stl: "none",
}

cc_binary {
    name: "gzip",
    defaults: ["gzip_defaults"],
    srcs: ["src/test/minigzip.c"],
}
```

## 名称解析

Soong为不同目录中的模块提供了指定相同名称的能力。只要每个模块在一个单独的名称空间中声明。 命名空间可以这样声明：

```go
soong_namespace {
    imports: ["path/to/otherNamespace1", "path/to/otherNamespace2"],
}
```

每个Soong模块都会根据其在树中的位置分配一个名称空间，除非找不到soong_namespace模块，否则每个Soong模块都被认为位于当前目录或最接近的父目录中的Android.bp中的soong_namespace所定义的名称空间中。在这种情况下，该模块被认为处于隐式根目录命名空间。

当Soong试图解决声明在我的模块M中命名空间N的依赖关系D时，它导入命名空间I1，I2，I3 ...，那么如果D是形式为`“// namespace：module”`的完全限定名称，那么只会在指定的名称空间中搜索指定的模块名称。否则，Soong将首先查找声明在名字控制N中的模块名D。如果这个模块不存在，Soong将在名字空间l1，l2，l3...中查找模块名D，最后，Soong将在根名字空间中查找。

在我们完全转换成Make到Soong之前，Make产品配置需要指定一个值PRODUCT_SOONG_NAMESPACES。它的值应该是空格分隔的命名空间列表，用`m`命令把Soong导出到Make编译。在Make to Soong完全转换之后，启用命名空间的细节可能会发生变化。

## 格式化

Soong 包含了一个 blueprint 文件的格式化器，类似于 gofmt。使用以下命令来递归格式化当前目录中的所有 Android.bp 文件：

```go
bpfmt -w .
```

标准格式包括 4 个空格的缩进，包含多个元素的列表中，每个元素之后的换行符，并且始终包括列表和 maps中的逗号。

## 转换Android.mk文件

Soong包括一个工具执行第一过程转换Android.mk文件到Android.bp文件：

```go
androidmk Android.mk > Android.bp
```

该工具可以转换变量，模块，注释和一些条件，但任何自定义的 Makefile 规则，复杂条件或额外的 include 必须手动转换。

## Android.mk和Android.bp之间的差异

- Android.mk文件中经常包含多个模块具有相同的名字（例如，对于同时拥有静态和动态版本的库，或同时供主机和设备使用的库）。Android.pb文件要求每个模块有唯一的名字，但是每个模块能内置多个变化，例如添加`host_supported: true`。Androidmk转换器将产生多个冲突的模块，必须手动合并到单个模块的`target: { android: { }, host: ( )}`内。

## 编译逻辑

编译逻辑是用Go语音的[blueprint](https://godoc.org/github.com/google/blueprint)框架写的。编译逻辑接收模块定义，并利用反射和编译规则解析为Go数据结构。构建规则由blueprint收集并写入[ninja](https://ninja-build.org/)构建文件。

## FAQ

### 如何写一个条件？

Soong故意不支持Android.bp文件中的条件。作为替换，需要条件的复杂的构建规则已被Go语言处理。可以使用高级语言特征来跟踪由条件引入的隐式依赖关系。大多数条件将被转换为map属性，map中的一个值将被选中并附加到顶级属性。

例如，支持特定架构的文件：

```go
cc_library {
    ...
    srcs: ["generic.cpp"],
    arch: {
        arm: {
            srcs: ["arm.cpp"],
        },
        x86: {
            srcs: ["x86.cpp"],
        },
    },
}
```

有关产品变量或环境变量的更复杂条件的示例，请参阅[art/build/art.go](https://android.googlesource.com/platform/art/+/master/build/art.go)或者[external/llvm/soong/llvm.go](https://android.googlesource.com/platform/external/llvm/+/master/soong/llvm.go)。



