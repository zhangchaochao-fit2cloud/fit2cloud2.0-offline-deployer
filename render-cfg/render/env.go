package render

import (
	"os"

	"github.com/joho/godotenv"
)

// LoadEnvFiles 加载多个env文件(后者覆盖前者)
func LoadEnvFiles(files []string) (map[string]interface{}, error) {
	merged := make(map[string]interface{})

	for _, f := range files {
		if _, err := os.Stat(f); os.IsNotExist(err) {
			continue // 忽略不存在的文件
		}

		envs, err := godotenv.Read(f)
		if err != nil {
			return nil, err
		}

		for k, v := range envs {
			merged[k] = v
		}
	}

	return merged, nil
}
