package render

import (
	crypto_rand "crypto/rand"
	"fmt"
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
	e.discoverTemplates()
	return e
}

func (e *Engine) discoverTemplates() {
	filepath.Walk(e.cfg.TemplateDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}

		ext := filepath.Ext(path)
		if ext == ".tmpl" || ext == ".tpl" {
			e.templates = append(e.templates, path)
		}
		return nil
	})
}

func (e *Engine) Run(envData map[string]interface{}) error {
	for _, tmplPath := range e.templates {
		content, err := os.ReadFile(tmplPath)
		if err != nil {
			return fmt.Errorf("读取模板 %s 失败: %v", tmplPath, err)
		}

		mode := "error"
		if !e.cfg.StrictMode {
			mode = "zero"
		}

		tmpl := template.Must(
			template.New(filepath.Base(tmplPath)).
				Funcs(e.funcMap).
				Option("missingkey="+mode).
				Parse(string(content)),
		)

		var buf strings.Builder
		if err := tmpl.Execute(&buf, envData); err != nil {
			return fmt.Errorf("渲染模板 %s 失败: %v", filepath.Base(tmplPath), err)
		}

	relPath, err := filepath.Rel(e.cfg.TemplateDir, tmplPath)
	if err != nil {
		return fmt.Errorf("计算相对路径失败: %v", err)
	}
	outputName := strings.TrimSuffix(relPath, filepath.Ext(relPath))
	outputPath := filepath.Join(e.cfg.OutputDir, outputName)
		if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
			return err
		}
		if err := os.WriteFile(outputPath, []byte(buf.String()), 0644); err != nil {
			return err
		}
	}
	return nil
}

func (e *Engine) initFuncMap() {
	e.funcMap = sprig.TxtFuncMap()

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

	e.funcMap["required"] = func(args ...interface{}) (interface{}, error) {
		var msg string
		var val interface{}
		switch len(args) {
		case 1:
			val = args[0]
		case 2:
			m, ok := args[0].(string)
			if !ok {
				return nil, fmt.Errorf("required: 第一个参数必须是字符串提示信息")
			}
			msg, val = m, args[1]
		default:
			return nil, fmt.Errorf("required: 需要 1 或 2 个参数")
		}
		if val == nil || val == "" {
			if msg == "" {
				msg = "缺少必填变量"
			}
			return nil, fmt.Errorf("%s", msg)
		}
		return val, nil
	}

	e.funcMap["encrypt"] = func(key string, val interface{}) (string, error) {
		s, ok := val.(string)
		if !ok {
			return "", fmt.Errorf("加密值必须是字符串")
		}

		for _, suffix := range e.cfg.EncryptKeys {
			if strings.HasSuffix(key, suffix) {
				return Encrypt(s)
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

	e.funcMap["generatePassword"] = func(length int) (string, error) {
		if length <= 0 {
			length = 16
		}
		const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
		result := make([]byte, length)
		_, err := crypto_rand.Read(result)
		if err != nil {
			return "", err
		}
		for i := range result {
			result[i] = chars[int(result[i])%len(chars)]
		}
		return string(result), nil
	}
}
