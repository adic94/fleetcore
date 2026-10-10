import { CanActivate, ExecutionContext, Injectable, UnauthorizedException, ForbiddenException } from '@nestjs/common';
import type { Request } from 'express';
import { DbService, TenantContext } from './db.service';

/**
 * Ustala kontekst spółki dla żądania.
 *
 * SZKIELET: uwierzytelnianie (sesja, MFA, OIDC, klienci API OAuth) powstaje w fazie 0 —
 * docs/04-api-integrations.md i docs/16-platforma-integracji.md. Do tego czasu w trybie
 * development użytkownika wskazuje nagłówek `X-Dev-User`; poza development żądanie jest odrzucane.
 *
 * Niezmienne niezależnie od sposobu logowania: lista spółek pochodzi z core.user_company_access,
 * a aktywna spółka z nagłówka `X-Active-Company` musi być na tej liście.
 */
@Injectable()
export class TenantGuard implements CanActivate {
  constructor(private readonly db: DbService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<Request & { tenant?: TenantContext }>();

    if (process.env.NODE_ENV !== 'development') {
      throw new UnauthorizedException('Uwierzytelnianie nie jest jeszcze zaimplementowane (faza 0)');
    }
    const userId = Number(req.header('x-dev-user'));
    if (!Number.isInteger(userId) || userId <= 0) throw new UnauthorizedException();

    const grants = await this.db.userCompanies(userId);
    const companyIds = grants.map((g) => Number(g.company_id));
    if (companyIds.length === 0) throw new ForbiddenException('Brak nadań do spółek');

    const requested = Number(req.header('x-active-company') ?? companyIds[0]);
    if (!companyIds.includes(requested)) throw new ForbiddenException('Spółka spoza nadań');

    req.tenant = { userId, companyIds, activeCompanyId: requested };
    return true;
  }
}
