package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/fsnotify/fsnotify"
)

type Domain struct {
	Main string `json:"main"`
}

type Certificate struct {
	Domain      Domain `json:"domain"`
	Certificate string `json:"certificate"`
	Key         string `json:"key"`
}

type LetsEncrypt struct {
	Certificates []Certificate `json:"Certificates"`
}

type AcmeConfig map[string]LetsEncrypt

const (
	proxyPath    = "/data/coolify/proxy"
	acmeFilePath = proxyPath + "/acme.json"
	certsPath    = proxyPath + "/certs/acme"
	debounceTime = 1 * time.Second
)

func main() {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Fatal(err)
	}
	defer watcher.Close()

	var debounceTimer *time.Timer
	var debounceChan <-chan time.Time

	processAcme := func() {
		log.Println("Processing acme.json...")
		data, err := os.ReadFile(acmeFilePath)
		if err != nil {
			log.Println("Error reading file:", err)
			return
		}

		var config AcmeConfig
		err = json.Unmarshal(data, &config)
		if err != nil {
			log.Println("Error unmarshaling JSON:", err)
			return
		}

		for _, resolver := range config {
			for _, cert := range resolver.Certificates {
				if cert.Domain.Main == "" {
					continue
				}

				dirPath := filepath.Join(certsPath, cert.Domain.Main)
				if err := os.MkdirAll(dirPath, 0755); err != nil {
					log.Printf("Error creating directory for %s: %v", cert.Domain.Main, err)
					continue
				}

				decodedCert, err := base64.StdEncoding.DecodeString(cert.Certificate)
				if err != nil {
					log.Printf("Error decoding cert for %s: %v", cert.Domain.Main, err)
					continue
				}

				decodedKey, err := base64.StdEncoding.DecodeString(cert.Key)
				if err != nil {
					log.Printf("Error decoding key for %s: %v", cert.Domain.Main, err)
					continue
				}

				certPath := filepath.Join(dirPath, "cert.pem")
				if err := os.WriteFile(certPath, decodedCert, 0644); err != nil {
					log.Printf("Error writing cert for %s: %v", cert.Domain.Main, err)
					continue
				}

				keyPath := filepath.Join(dirPath, "key.pem")
				if err := os.WriteFile(keyPath, decodedKey, 0600); err != nil {
					log.Printf("Error writing key for %s: %v", cert.Domain.Main, err)
					continue
				}

				fmt.Printf("Successfully updated %s\n", cert.Domain.Main)
			}
		}
	}

	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}

				if event.Name == acmeFilePath && (event.Has(fsnotify.Write) || event.Has(fsnotify.Create)) {
					if debounceTimer != nil {
						debounceTimer.Stop()
					}
					debounceTimer = time.NewTimer(debounceTime)
					debounceChan = debounceTimer.C
				}

			case <-debounceChan:
				debounceChan = nil
				processAcme()

			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				log.Println("Watcher error:", err)
			}
		}
	}()

	processAcme()

	err = watcher.Add(proxyPath)
	if err != nil {
		log.Fatalf("Failed to add watcher for %s: %v", proxyPath, err)
	}

	log.Printf("Watching for %s changes...\n", acmeFilePath)

	select {}
}
