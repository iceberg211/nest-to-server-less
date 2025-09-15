import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Param,
  Delete,
  ParseIntPipe,
} from '@nestjs/common';
import { FormDataService } from './form-data.service';
import type { CreateFormDataDto, UpdateFormDataDto } from './form-data.service';

@Controller('form-data')
export class FormDataController {
  constructor(private readonly formDataService: FormDataService) {}

  @Post()
  create(@Body() createFormDataDto: CreateFormDataDto) {
    return this.formDataService.create(createFormDataDto);
  }

  @Get()
  findAll() {
    return this.formDataService.findAll();
  }

  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.formDataService.findOne(id);
  }

  @Patch(':id')
  update(
    @Param('id', ParseIntPipe) id: number,
    @Body() updateFormDataDto: UpdateFormDataDto,
  ) {
    return this.formDataService.update(id, updateFormDataDto);
  }

  @Delete(':id')
  remove(@Param('id', ParseIntPipe) id: number) {
    return this.formDataService.remove(id);
  }
}