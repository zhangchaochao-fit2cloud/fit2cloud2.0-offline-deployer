package main

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"log"

	"render-cfg/render"
)

func main() {
	// 命令行参数
	var (
		tmplDir      = flag.String("t", "./templates", "模板目录路径")
		outputDir    = flag.String("o", "./output", "输出目录路径")
		envFiles     = flag.StringSlice("e", []string{".env"}, "环境变量文件(可多个，后者覆盖前者)")
		strict       = flag.Bool("strict", false, "启用严格模式(校验必填变量)")
		encryptFlags = flag.StringSlice("encrypt", []string{"PASSWORD", "SECRET", "KEY"}, "需加密的字段后缀")
	)
	flag.Parse()

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
		log.Fatal("渲染失败: ", err)
	}

	fmt.Printf("配置生成完成! 输出目录: %s\n", *outputDir)
}
