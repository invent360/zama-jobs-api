package logic

import (
	"fmt"
	"math/rand"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/zama/job-processor/model"
)

type JobProcessor struct {
	SuccessRate        int
	MinProcessingTime  time.Duration
	MaxProcessingTime  time.Duration
	logger             *logrus.Logger
}

func NewJobProcessor() *JobProcessor {
	return &JobProcessor{
		SuccessRate:       90,
		MinProcessingTime: 1 * time.Second,
		MaxProcessingTime: 6 * time.Second,
		logger:            logrus.StandardLogger(),
	}
}

func (p *JobProcessor) WithSuccessRate(rate int) *JobProcessor {
	if rate > 100 {
		rate = 100
	}
	p.SuccessRate = rate
	return p
}

func (p *JobProcessor) WithProcessingTime(min, max time.Duration) *JobProcessor {
	p.MinProcessingTime = min
	p.MaxProcessingTime = max
	return p
}

func (p *JobProcessor) Process(event model.JobEvent) model.JobCompletionEvent {
	payload := "<no payload>"
	if event.Payload != nil {
		payload = *event.Payload
	}

	p.logger.WithFields(logrus.Fields{
		"job_id": event.JobID,
	}).Infof("Processing job: %s", payload)

	// Simulate job processing
	processingRange := p.MaxProcessingTime - p.MinProcessingTime
	processingTime := p.MinProcessingTime + time.Duration(rand.Int63n(int64(processingRange)))
	time.Sleep(processingTime)

	// Simulate success/failure based on configured success rate
	success := rand.Intn(100) < p.SuccessRate

	if success {
		p.logger.WithFields(logrus.Fields{
			"job_id": event.JobID,
		}).Info("Job completed successfully")

		result := fmt.Sprintf("Job processed successfully in %dms", processingTime.Milliseconds())
		return model.JobCompletionEvent{
			JobID:       event.JobID,
			Status:      model.JobStatusCompleted,
			Result:      &result,
			Error:       nil,
			CompletedAt: time.Now().Unix(),
		}
	} else {
		p.logger.WithFields(logrus.Fields{
			"job_id": event.JobID,
		}).Error("Job failed")

		errorMsg := "Simulated processing failure"
		return model.JobCompletionEvent{
			JobID:       event.JobID,
			Status:      model.JobStatusFailed,
			Result:      nil,
			Error:       &errorMsg,
			CompletedAt: time.Now().Unix(),
		}
	}
}