import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

export interface CreateFormDataDto {
  name: string;
  email: string;
}

export interface UpdateFormDataDto {
  name?: string;
  email?: string;
}

@Injectable()
export class FormDataService {
  constructor(private prisma: PrismaService) {}

  async create(data: CreateFormDataDto) {
    return this.prisma.formData.create({
      data,
    });
  }

  async findAll() {
    return this.prisma.formData.findMany({
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: number) {
    return this.prisma.formData.findUnique({
      where: { id },
    });
  }

  async update(id: number, data: UpdateFormDataDto) {
    return this.prisma.formData.update({
      where: { id },
      data,
    });
  }

  async remove(id: number) {
    return this.prisma.formData.delete({
      where: { id },
    });
  }
}