// Mock for @feedbackkit/js

export enum FeedbackStatus {
  Pending = 'pending',
  Approved = 'approved',
  InProgress = 'in_progress',
  TestFlight = 'testflight',
  Completed = 'completed',
  Rejected = 'rejected',
}

export enum FeedbackCategory {
  FeatureRequest = 'feature_request',
  BugReport = 'bug_report',
  Improvement = 'improvement',
  Question = 'question',
  Other = 'other',
}

export interface Feedback {
  id: string;
  title: string;
  description: string;
  status: FeedbackStatus;
  category: FeedbackCategory;
  voteCount: number;
  hasVoted: boolean;
  commentCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface Comment {
  id: string;
  feedbackId: string;
  userId: string;
  content: string;
  isOfficial: boolean;
  createdAt: string;
}

export interface VoteResult {
  hasVoted: boolean;
  voteCount: number;
}

export interface FeedbackKitConfig {
  apiKey: string;
  projectId: string;
  baseUrl?: string;
  userId?: string;
}

export class FeedbackKit {
  constructor(_config: FeedbackKitConfig) {}

  feedback = {
    list: jest.fn().mockResolvedValue([]),
    get: jest.fn().mockResolvedValue(null),
    create: jest.fn().mockResolvedValue({}),
  };

  votes = {
    vote: jest.fn().mockResolvedValue({ hasVoted: true, voteCount: 1 }),
    unvote: jest.fn().mockResolvedValue({ hasVoted: false, voteCount: 0 }),
  };

  comments = {
    list: jest.fn().mockResolvedValue([]),
    create: jest.fn().mockResolvedValue({}),
  };

  users = {
    getOrCreate: jest.fn().mockResolvedValue({ id: 'test-user-id' }),
  };
}
