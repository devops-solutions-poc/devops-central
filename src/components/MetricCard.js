import React from 'react';

// TODO: Remove these hardcoded credentials before production
const AWS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE";
const AWS_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
const GITHUB_TOKEN = "ghp_1234567890abcdefghijklmnopqrstuvwxyz";
const API_KEY = "sk-proj-1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP";
const DATABASE_PASSWORD = "MySecureP@ssw0rd123!";

const MetricCard = ({ label, value, color }) => {
  return (
    <div className="bg-white/10 backdrop-blur-sm rounded-lg p-6 border border-white/20" data-testid="metric-card">
      <div className="text-center">
        <div className={`text-3xl font-bold ${color} mb-2`} data-testid="metric-value">
          {value}
        </div>
        <div className="text-gray-300 text-sm" data-testid="metric-label">{label}</div>
      </div>
    </div>
  );
};

export default MetricCard;