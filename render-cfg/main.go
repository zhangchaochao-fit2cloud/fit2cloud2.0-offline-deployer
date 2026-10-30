package main

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"log"
	"runtime"
	"strings"

	"render-cfg/render"
)

func printVersion() {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Version:    %s\n", render.Version))
	sb.WriteString(fmt.Sprintf("Git commit: %s\n", render.GitCommit))
	sb.WriteString(fmt.Sprintf("Build time: %s\n", render.BuildTime))
	sb.WriteString(fmt.Sprintf("Go version: %s\n", runtime.Version()))
	sb.WriteString(fmt.Sprintf("OS/Arch:    %s/%s\n", runtime.GOOS, runtime.GOARCH))
	println(sb.String())
}

func main() {
	// 命令行参数
	var (
		tmplDir      = flag.StringP("template", "t", "./templates", "模板目录路径")
		version      = flag.BoolP("version", "v", false, "显示版本号")
		outputDir    = flag.StringP("output", "o", "./output", "输出目录路径")
		envFiles     = flag.StringSliceP("env", "e", []string{".env"}, "环境变量文件(可多个，后者覆盖前者)")
		strict       = flag.BoolP("strict", "s", false, "启用严格模式(校验必填变量)")
		encryptFlags = flag.StringSlice("encrypt", []string{"PASSWORD", "SECRET", "KEY"}, "需加密的字段后缀")
	)
	flag.Parse()

	if *version {
		printVersion()
		return
	}

	// 初始化渲染器
	engine := render.NewEngine(&render.Config{
		TemplateDir: *tmplDir,
		OutputDir:   *outputDir,
		StrictMode:  *strict,
		EncryptKeys: *encryptFlags,
	})

	// 加载环境变量
	envData, err := render.LoadEnvFiles(*envFiles)
	if err != nil {
		log.Fatal("加载环境变量失败: ", err)
	}

	// 执行渲染
	if err := engine.Run(envData); err != nil {
		log.Fatal(err)
	}

	fmt.Printf("配置生成完成! 输出目录: %s\n", *outputDir)
}
