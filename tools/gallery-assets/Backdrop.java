package com.example.orders;

import java.math.BigDecimal;
import java.util.List;

/**
 * The backdrop the gallery is recorded over.
 *
 * Not a test fixture and not dead code: it is a prop. Every clip in the gallery
 * needs SOMETHING believable behind the confetti, and "whatever Victor happened
 * to have open" is both unrepeatable and a privacy problem — two runs a month
 * apart would show two different desktops, and one of them would show his mail.
 *
 * So the backdrop is checked in: an editor window with the kind of code a room
 * is actually looking at when an effect fires. Long enough to fill a 16:10
 * screen, ordinary enough that nobody reads it instead of watching the effect.
 */
public class OrderService {

    private final OrderRepository repository;
    private final CustomerRepository customers;
    private final PricingClient pricing;
    private final NotificationGateway notifications;

    public OrderService(OrderRepository repository,
                        CustomerRepository customers,
                        PricingClient pricing,
                        NotificationGateway notifications) {
        this.repository = repository;
        this.customers = customers;
        this.pricing = pricing;
        this.notifications = notifications;
    }

    public OrderDto placeOrder(PlaceOrderRequest request) {
        Customer customer = customers.findById(request.customerId())
                .orElseThrow(() -> new CustomerNotFound(request.customerId()));

        if (customer.isBlocked()) {
            throw new IllegalStateException("Customer " + customer.id() + " is blocked");
        }

        List<OrderLine> lines = request.lines().stream()
                .map(line -> new OrderLine(line.sku(), line.quantity(), pricing.priceOf(line.sku())))
                .toList();

        BigDecimal total = lines.stream()
                .map(OrderLine::lineTotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        if (total.compareTo(customer.creditLimit()) > 0) {
            throw new CreditLimitExceeded(customer.id(), total, customer.creditLimit());
        }

        Order order = new Order(customer.id(), lines, total, OrderStatus.NEW);
        repository.save(order);

        notifications.orderPlaced(customer.email(), order.id(), total);
        return OrderDto.from(order);
    }

    public void cancel(long orderId, String reason) {
        Order order = repository.findById(orderId)
                .orElseThrow(() -> new OrderNotFound(orderId));

        if (order.status() == OrderStatus.SHIPPED) {
            throw new IllegalStateException("A shipped order cannot be cancelled");
        }

        order.markCancelled(reason);
        repository.save(order);
        notifications.orderCancelled(order.id(), reason);
    }

    public List<OrderDto> historyFor(long customerId) {
        return repository.findByCustomerId(customerId).stream()
                .filter(order -> order.status() != OrderStatus.DRAFT)
                .sorted(Comparator.comparing(Order::placedAt).reversed())
                .map(OrderDto::from)
                .toList();
    }
}
