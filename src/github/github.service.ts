import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import axios from 'axios';

export interface GitHubUser {
  id: number;
  login: string;
  name: string;
  email: string;
  avatar_url: string;
  bio: string;
  public_repos: number;
  followers: number;
  following: number;
  created_at: string;
}

@Injectable()
export class GitHubService {
  async getUserInfo(token: string): Promise<GitHubUser> {
    try {
      const response = await axios.get('https://api.github.com/user', {
        headers: {
          Authorization: `token ${token}`,
          'User-Agent': 'NestJS-App',
        },
      });

      return response.data;
    } catch (error) {
      if (error.response?.status === 401) {
        throw new HttpException('Invalid GitHub token', HttpStatus.UNAUTHORIZED);
      }

      throw new HttpException(
        'Failed to fetch GitHub user information',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }
}