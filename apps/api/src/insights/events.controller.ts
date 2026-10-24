import { Body, Controller, HttpCode, Post, Req, UseGuards } from '@nestjs/common';
import { Request } from 'express';
import { OptionalJwtAuthGuard } from '../common/guards/optional-jwt-auth.guard';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { InsightsService } from './insights.service';
import { RecordEventsDto } from './dto/record-events.dto';

@Controller('events')
export class EventsController {
  constructor(private readonly insightsService: InsightsService) {}

  /** Usage telemetry from the JustHeal app (screen views + button taps).
   *  Works before login too (anonymous), so the login/registration funnel
   *  is visible — see OptionalJwtAuthGuard. */
  @Post()
  @HttpCode(202)
  @UseGuards(OptionalJwtAuthGuard)
  record(@Body() dto: RecordEventsDto, @Req() req: Request & { user?: JwtPayload }) {
    return this.insightsService.recordEvents(dto, req.user);
  }
}
