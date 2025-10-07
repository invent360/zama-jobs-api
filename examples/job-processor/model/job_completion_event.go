package model

import (
	"github.com/google/uuid"
)

type JobCompletionEvent struct {
	JobID       uuid.UUID  `json:"job_id"`
	Status      JobStatus  `json:"status"`
	Result      *string    `json:"result,omitempty"`
	Error       *string    `json:"error,omitempty"`
	CompletedAt int64      `json:"completed_at"`
}