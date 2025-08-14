package render

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"text/template"

	"github.com/Masterminds/sprig/v3"
)

type Engine struct {
	cfg       *Config
	templates []string
	funcMap   template.FuncMap
}

type Config struct {
	TemplateDir string
	OutputDir   string
	StrictMode  bool
	EncryptKeys []string
}

func NewEngine(cfg *Config) *Engine {
	e := &Engine{cfg: cfg}
	e.initFuncMap()

	// 发现模板文件
	e.discoverTemplates()
	return e
}

// 自动发现模板文件(.tmpl/.tpl)
func (e *Engine) discoverTemplates() {
	filepath.Walk(e.cfg.TemplateDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}

		ext := filepath.Ext(path)
		if ext == ".tmpl" || ext == ".tpl" {
			e.templates = append(e.templates, path)
		}
		return nil
	})
}

// Run 渲染所有模板
func (e *Engine) Run(envData map[string]interface{}) error {
	for _, tmplPath := range e.templates {
		content, err := ioutil.ReadFile(tmplPath)
		if err != nil {
			return fmt.Errorf("读取模板 %s 失败: %v", tmplPath, err)
		}

		mode := "error"
		if !e.cfg.StrictMode {
			mode = "zero"
		}

		// 执行渲染
		tmpl := template.Must(
			template.New(filepath.Base(tmplPath)).
				Funcs(e.funcMap).
				Option("missingkey=" + mode).
				Parse(string(content)),
		)

		var buf strings.Builder
		if err := tmpl.Execute(&buf, envData); err != nil {
			return fmt.Errorf("渲染模板 %s 失败: %v", tmplPath, err)
		}

		// 写入输出文件(去除模板后缀)
		outputPath := filepath.Join(e.cfg.OutputDir, strings.TrimSuffix(filepath.Base(tmplPath), filepath.Ext(tmplPath)))
		if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
			return err
		}
		if err := ioutil.WriteFile(outputPath, []byte(buf.String()), 0644); err != nil {
			return err
		}
	}
	return nil
}

// 自定义函数: 条件加密
func (e *Engine) encryptIfNeeded(key string, val interface{}) (string, error) {
	s, ok := val.(string)
	if !ok {
		return "", fmt.Errorf("加密值必须是字符串")
	}

	// 检查是否需要加密
	for _, suffix := range e.cfg.EncryptKeys {
		if strings.HasSuffix(key, suffix) {
			return Encrypt(s), nil // 调用加密逻辑
		}
	}
	return s, nil
}

// 初始化模板函数
func (e *Engine) initFuncMap() {
	e.funcMap = sprig.TxtFuncMap()

	// 自定义函数
	e.funcMap["isset"] = func(m map[string]interface{}, key string) bool {
		_, ok := m[key]
		return ok
	}

	e.funcMap["regexMatch"] = func(pattern, s string) bool {
		match, _ := regexp.MatchString(pattern, s)
		return match
	}

	e.funcMap["default"] = func(defVal, input interface{}) interface{} {
		if input == nil || input == "" {
			return defVal
		}
		return input
	}

	e.funcMap["required"] = func(val interface{}) (interface{}, error) {
		if val == nil || val == "" {
			return nil, fmt.Errorf("缺少必填变量")
		}
		return val, nil
	}

	e.funcMap["encrypt"] = func(key string, val interface{}) (string, error) {
		s, ok := val.(string)
		if !ok {
			return "", fmt.Errorf("加密值必须是字符串")
		}

		// 检查是否需要加密
		for _, suffix := range e.cfg.EncryptKeys {
			if strings.HasSuffix(key, suffix) {
				return Encrypt(s), nil // 调用加密逻辑
			}
		}
		return s, nil
	}

	e.funcMap["toBool"] = func(val interface{}) bool {
		switch v := val.(type) {
		case bool:
			return v
		case string:
			return strings.EqualFold(v, "true") || v == "1"
		case int, float64:
			return v != 0
		default:
			return false
		}
	}

	e.funcMap["split"] = strings.Split
	e.funcMap["join"] = strings.Join
}
