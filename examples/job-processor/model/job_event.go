package model

import (
	"github.com/google/uuid"
)

type JobEvent struct {
	JobID     uuid.UUID  `json:"job_id"`
	Status    JobStatus  `json:"status"`
	Payload   *string    `json:"payload,omitempty"`
	Result    *string    `json:"result,omitempty"`
	Error     *string    `json:"error,omitempty"`
	Timestamp int64      `json:"timestamp"`
}