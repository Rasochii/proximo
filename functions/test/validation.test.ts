import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  DomainError,
  parseAcceptingEntriesInput,
  parseAdvanceInput,
  parseBarberStatusInput,
  parseJoinQueueInput,
  parseTicketInput,
} from '../src/domain';

const requestId = '3b241101-e2bb-4255-8caf-4136c566a962';

function invalid(fn: () => unknown): void {
  assert.throws(fn, (e: unknown) => e instanceof DomainError && e.code === 'invalid-argument');
}

describe('validação das callables', () => {
  it('aceita uma entrada válida com valores padrão', () => {
    assert.deepEqual(parseJoinQueueInput({ requestId, shopId: 'ze', name: 'Lucas', serviceId: 'corte' }), {
      requestId,
      shopId: 'ze',
      name: 'Lucas',
      serviceId: 'corte',
      source: 'link',
      preferredBarberId: null,
    });
    assert.equal(parseAdvanceInput({ requestId, shopId: 'ze', expectedServingTicketId: null }).outcome, 'done');
  });

  it('no avanço da fila, exige dizer quem está na cadeira: um ticket ou ninguém', () => {
    assert.equal(parseAdvanceInput({ requestId, shopId: 'ze', expectedServingTicketId: null }).expectedServingTicketId, null);
    assert.equal(parseAdvanceInput({ requestId, shopId: 'ze', expectedServingTicketId: 't1' }).expectedServingTicketId, 't1');
    // Ausente não vale como "ninguém": um cliente que perdesse o campo ficaria sem a conferência.
    assert.throws(
      () => parseAdvanceInput({ requestId, shopId: 'ze' }),
      (e: unknown) => e instanceof DomainError && e.code === 'invalid-argument' && e.details?.field === 'expectedServingTicketId',
    );
    invalid(() => parseAdvanceInput({ requestId, shopId: 'ze', expectedServingTicketId: 42 }));
    invalid(() => parseAdvanceInput({ requestId, shopId: 'ze', expectedServingTicketId: 'a/b' }));
  });

  it('normaliza o requestId para minúsculas', () => {
    assert.equal(parseTicketInput({ requestId: requestId.toUpperCase(), shopId: 'ze', ticketId: 't1' }).requestId, requestId);
  });

  it('rejeita payloads malformados', () => {
    invalid(() => parseJoinQueueInput(null));
    invalid(() => parseJoinQueueInput([]));
    invalid(() => parseJoinQueueInput({ requestId: 'abc', shopId: 'ze', serviceId: 'corte' }));
    invalid(() => parseJoinQueueInput({ requestId, shopId: '../shops', serviceId: 'corte' }));
    invalid(() => parseJoinQueueInput({ requestId, shopId: 'ze', serviceId: 'corte', source: 'hack' }));
    invalid(() => parseAdvanceInput({ requestId, shopId: 'ze', expectedServingTicketId: null, outcome: 'cancelled' }));
    invalid(() => parseBarberStatusInput({ requestId, shopId: 'ze', status: 'busy' }));
    invalid(() => parseAcceptingEntriesInput({ requestId, shopId: 'ze', accepting: 'yes' }));
    invalid(() => parseTicketInput({ requestId, shopId: 'ze', ticketId: 'x'.repeat(65) }));
  });
});
