package main

import (
	"encoding/json"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/nats-io/nats.go"
	"github.com/sirupsen/logrus"
	"github.com/zama/job-processor/logic"
	"github.com/zama/job-processor/model"
)

const (
	JobSubmitSubject   = "jobs.submit"
	JobCompleteSubject = "jobs.complete"
)

func main() {
	// Initialize logger
	logger := logrus.New()
	logger.SetLevel(logrus.InfoLevel)
	logger.SetFormatter(&logrus.TextFormatter{
		FullTimestamp: true,
	})

	logger.Info("Job Processor starting...")

	// Get NATS URL from environment or use default
	natsURL := os.Getenv("NATS_URL")
	if natsURL == "" {
		natsURL = "nats://localhost:4222"
	}

	logger.Infof("Connecting to NATS at %s", natsURL)

	// Connect to NATS
	nc, err := nats.Connect(natsURL)
	if err != nil {
		logger.Fatalf("Failed to connect to NATS: %v", err)
	}
	defer nc.Close()

	logger.Info("Connected to NATS successfully")

	// Create job processor
	processor := logic.NewJobProcessor()

	// Subscribe to job submissions
	subscription, err := nc.Subscribe(JobSubmitSubject, func(msg *nats.Msg) {
		var event model.JobEvent
		if err := json.Unmarshal(msg.Data, &event); err != nil {
			logger.WithError(err).Error("Failed to parse job event")
			return
		}

		logger.WithFields(logrus.Fields{
			"job_id": event.JobID,
		}).Info("Received job")

		// Process job asynchronously
		go func(e model.JobEvent) {
			completion := processor.Process(e)

			// Publish completion event
			completionData, err := json.Marshal(completion)
			if err != nil {
				logger.WithError(err).WithFields(logrus.Fields{
					"job_id": completion.JobID,
				}).Error("Failed to serialize completion event")
				return
			}

			if err := nc.Publish(JobCompleteSubject, completionData); err != nil {
				logger.WithError(err).WithFields(logrus.Fields{
					"job_id": completion.JobID,
				}).Error("Failed to publish completion")
			} else {
				logger.WithFields(logrus.Fields{
					"job_id": completion.JobID,
				}).Info("Published completion")
			}
		}(event)
	})

	if err != nil {
		logger.Fatalf("Failed to subscribe to %s: %v", JobSubmitSubject, err)
	}
	defer subscription.Unsubscribe()

	logger.Infof("Listening for jobs on %s", JobSubmitSubject)

	// Wait for interrupt signal to gracefully shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Keep the main goroutine alive
	var wg sync.WaitGroup
	wg.Add(1)

	go func() {
		<-sigChan
		logger.Info("Shutting down...")
		wg.Done()
	}()

	wg.Wait()
	logger.Info("Job Processor stopped")
}