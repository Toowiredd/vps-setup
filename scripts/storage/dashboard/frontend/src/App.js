import React, { useState, useEffect } from "react";
import {
  ChakraProvider,
  Box,
  Grid,
  VStack,
  HStack,
  Text,
  Heading,
  Button,
  Progress,
  useToast,
  Container,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  Card,
  CardHeader,
  CardBody,
  SimpleGrid,
  Input,
  FormControl,
  FormLabel,
} from "@chakra-ui/react";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
} from "recharts";

const API_BASE = process.env.REACT_APP_API_BASE || "http://localhost:5000/api";

function App() {
  const [status, setStatus] = useState({ state: "idle" });
  const [metrics, setMetrics] = useState({});
  const [transfers, setTransfers] = useState([]);
  const [source, setSource] = useState("");
  const [target, setTarget] = useState("");
  const toast = useToast();

  // Fetch initial data
  useEffect(() => {
    fetchStatus();
    fetchMetrics();
    fetchTransfers();
  }, []);

  // Set up real-time updates
  useEffect(() => {
    const events = new EventSource(`${API_BASE}/events`);

    events.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === "progress") {
        toast({
          title: "Progress Update",
          description: data.message,
          status: "info",
          duration: 3000,
          isClosable: true,
        });
      } else if (data.type === "error") {
        toast({
          title: "Error",
          description: data.message,
          status: "error",
          duration: 5000,
          isClosable: true,
        });
      }
    };

    return () => events.close();
  }, [toast]);

  // Polling for updates
  useEffect(() => {
    const interval = setInterval(() => {
      fetchStatus();
      fetchMetrics();
      fetchTransfers();
    }, 5000);

    return () => clearInterval(interval);
  }, []);

  const fetchStatus = async () => {
    try {
      const response = await fetch(`${API_BASE}/status`);
      const data = await response.json();
      setStatus(data);
    } catch (error) {
      console.error("Error fetching status:", error);
    }
  };

  const fetchMetrics = async () => {
    try {
      const response = await fetch(`${API_BASE}/metrics`);
      const data = await response.json();
      setMetrics(data);
    } catch (error) {
      console.error("Error fetching metrics:", error);
    }
  };

  const fetchTransfers = async () => {
    try {
      const response = await fetch(`${API_BASE}/transfers`);
      const data = await response.json();
      setTransfers(data.transfers);
    } catch (error) {
      console.error("Error fetching transfers:", error);
    }
  };

  const startMigration = async () => {
    try {
      const response = await fetch(`${API_BASE}/start`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ source, target }),
      });
      const data = await response.json();

      toast({
        title: "Migration Started",
        description: data.message,
        status: "success",
        duration: 5000,
        isClosable: true,
      });
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to start migration",
        status: "error",
        duration: 5000,
        isClosable: true,
      });
    }
  };

  const stopMigration = async () => {
    try {
      const response = await fetch(`${API_BASE}/stop`, {
        method: "POST",
      });
      const data = await response.json();

      toast({
        title: "Migration Stopped",
        description: data.message,
        status: "info",
        duration: 5000,
        isClosable: true,
      });
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to stop migration",
        status: "error",
        duration: 5000,
        isClosable: true,
      });
    }
  };

  return (
    <ChakraProvider>
      <Container maxW="container.xl" py={5}>
        <VStack spacing={5} align="stretch">
          {/* Header */}
          <Box p={5} shadow="md" borderWidth="1px" borderRadius="md">
            <Heading size="lg">Storage Migration Dashboard</Heading>
          </Box>

          {/* Control Panel */}
          <Card>
            <CardHeader>
              <Heading size="md">Control Panel</Heading>
            </CardHeader>
            <CardBody>
              <VStack spacing={4}>
                <HStack spacing={4} width="100%">
                  <FormControl>
                    <FormLabel>Source</FormLabel>
                    <Input
                      value={source}
                      onChange={(e) => setSource(e.target.value)}
                      placeholder="Source path"
                    />
                  </FormControl>
                  <FormControl>
                    <FormLabel>Target</FormLabel>
                    <Input
                      value={target}
                      onChange={(e) => setTarget(e.target.value)}
                      placeholder="Target path"
                    />
                  </FormControl>
                </HStack>
                <HStack spacing={4}>
                  <Button
                    colorScheme="blue"
                    onClick={startMigration}
                    isDisabled={status.state === "running"}>
                    Start Migration
                  </Button>
                  <Button
                    colorScheme="red"
                    onClick={stopMigration}
                    isDisabled={status.state !== "running"}>
                    Stop Migration
                  </Button>
                </HStack>
              </VStack>
            </CardBody>
          </Card>

          {/* Status and Metrics */}
          <SimpleGrid columns={3} spacing={5}>
            <Stat>
              <StatLabel>Status</StatLabel>
              <StatNumber>
                <Badge
                  colorScheme={
                    status.state === "running"
                      ? "green"
                      : status.state === "failed"
                      ? "red"
                      : "gray"
                  }>
                  {status.state}
                </Badge>
              </StatNumber>
              <StatHelpText>
                {status.start_time &&
                  `Started: ${new Date(
                    status.start_time * 1000
                  ).toLocaleString()}`}
              </StatHelpText>
            </Stat>
            <Stat>
              <StatLabel>CPU Usage</StatLabel>
              <StatNumber>{status.system_metrics?.cpu_usage}%</StatNumber>
              <Progress
                value={status.system_metrics?.cpu_usage}
                colorScheme="green"
                size="sm"
              />
            </Stat>
            <Stat>
              <StatLabel>Memory Usage</StatLabel>
              <StatNumber>{status.system_metrics?.memory_usage}%</StatNumber>
              <Progress
                value={status.system_metrics?.memory_usage}
                colorScheme="blue"
                size="sm"
              />
            </Stat>
          </SimpleGrid>

          {/* Transfer History */}
          <Card>
            <CardHeader>
              <Heading size="md">Transfer History</Heading>
            </CardHeader>
            <CardBody>
              <Table variant="simple">
                <Thead>
                  <Tr>
                    <Th>Source</Th>
                    <Th>Target</Th>
                    <Th>Status</Th>
                    <Th>Duration</Th>
                    <Th>Size</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {transfers.slice(-5).map((transfer, index) => (
                    <Tr key={index}>
                      <Td>{transfer.source}</Td>
                      <Td>{transfer.target}</Td>
                      <Td>
                        <Badge colorScheme={transfer.success ? "green" : "red"}>
                          {transfer.success ? "Success" : "Failed"}
                        </Badge>
                      </Td>
                      <Td>{Math.round(transfer.duration)}s</Td>
                      <Td>
                        {(transfer.file_size / 1024 / 1024).toFixed(2)} MB
                      </Td>
                    </Tr>
                  ))}
                </Tbody>
              </Table>
            </CardBody>
          </Card>

          {/* Performance Charts */}
          <Card>
            <CardHeader>
              <Heading size="md">Performance Metrics</Heading>
            </CardHeader>
            <CardBody>
              <Grid templateColumns="repeat(2, 1fr)" gap={6}>
                <Box>
                  <LineChart
                    width={500}
                    height={300}
                    data={metrics.historical?.transfers || []}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="timestamp" />
                    <YAxis />
                    <Tooltip />
                    <Legend />
                    <Line
                      type="monotone"
                      dataKey="duration"
                      stroke="#8884d8"
                      name="Duration (s)"
                    />
                  </LineChart>
                </Box>
                <Box>
                  <LineChart
                    width={500}
                    height={300}
                    data={metrics.historical?.transfers || []}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="timestamp" />
                    <YAxis />
                    <Tooltip />
                    <Legend />
                    <Line
                      type="monotone"
                      dataKey="bandwidth"
                      stroke="#82ca9d"
                      name="Bandwidth (MB/s)"
                    />
                  </LineChart>
                </Box>
              </Grid>
            </CardBody>
          </Card>
        </VStack>
      </Container>
    </ChakraProvider>
  );
}

export default App;
